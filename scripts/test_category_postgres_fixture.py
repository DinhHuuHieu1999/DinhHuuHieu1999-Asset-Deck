"""Offline contract checks; never connect to Docker or PostgreSQL."""
import importlib.util
import json
import time
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('category_fixture_test', Path(__file__).with_name('category-postgres-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class CategoryFixtureTests(unittest.TestCase):
    def test_no_opt_in_refuses_before_commands(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(m.client.Runtime, 'run') as run:
            with self.assertRaises(m.client.Refusal):
                m.execute(Path(folder), SimpleNamespace(execute_synthetic=False, image='sha256:'+'a'*64), m.client.Runtime())
            run.assert_not_called()

    def test_missing_each_file_fails_before_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.FILES:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('synthetic', encoding='utf-8')
            for name in m.FILES:
                p = root / name
                p.unlink()
                with patch.object(m.client.Runtime, 'run') as run:
                    with self.assertRaises(m.client.Refusal):
                        m.execute(root, SimpleNamespace(execute_synthetic=True, image='sha256:'+'a'*64), m.client.Runtime())
                    run.assert_not_called()
                p.write_text('synthetic', encoding='utf-8')

    def test_valid_exact_jest_result(self):
        m.validate_result(self.result())

    @staticmethod
    def result():
        return dict(success=True, numPassedTests=4, numTotalTests=4, numFailedTests=0,
                    numPendingTests=0, numRuntimeErrorTestSuites=0, numPassedTestSuites=1)

    def test_incomplete_or_skipped_is_never_pass(self):
        for key in self.result():
            value = self.result()
            value.pop(key)
            with self.assertRaises(m.client.Refusal):
                m.validate_result(value)
        for patch_value in ({'numPendingTests': 1}, {'success': False}, {'numPassedTests': True},
                            {'numPassedTests': 3}, {'numRuntimeErrorTestSuites': 1}):
            with self.assertRaises(m.client.Refusal):
                m.validate_result(dict(self.result(), **patch_value))

    def flow(self, root, ownership_bad=False, assertion_bad=False, running=False):
        calls = []
        identity = 'a' * 32
        database = 'asset_category_fixture_' + identity[:12]
        class Runtime:
            env = {}
            deadline = time.monotonic() + 120
            def run(self, command, **kwargs):
                calls.append(command)
                if command[:3] == ['docker', 'image', 'inspect']:
                    return ('sha256:' + 'b' * 64).encode()
                if command[:2] == ['docker', 'inspect']:
                    if '.Config.Labels' in command[3]:
                        # Permit initial ownership but refuse cleanup when requested.
                        count = sum(c[:2] == ['docker', 'inspect'] and '.Config.Labels' in c[3] for c in calls)
                        return json.dumps({m.client.LABEL: 'wrong' if ownership_bad and count >= 3 else identity}).encode()
                    if '.State.Running' in command[3]:
                        return json.dumps(running).encode()
                    return json.dumps({'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '59091'}]}).encode()
                if command[:2] == ['docker', 'exec'] and '-Atqc' in command:
                    return (database + '|fixture').encode()
                if command[0] == 'node':
                    result = CategoryFixtureTests.result()
                    if assertion_bad: result['numPassedTests'] = 3
                    destination = next(c.split('=', 1)[1] for c in command if c.startswith('--outputFile='))
                    Path(destination).write_text(json.dumps(result), encoding='utf-8')
                return b''
        with patch.object(m, 'preflight'), patch.object(m.secrets, 'token_hex', return_value=identity):
            try:
                result = m.execute(root, SimpleNamespace(image='sha256:'+'b'*64), Runtime())
            except m.client.Refusal:
                result = json.loads((root/'.local'/('asset-category-'+identity)/'result.json').read_text())
        return result, calls

    def test_mocked_flow_runs_once_and_stops_owned_container(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.FILES[:2]:
                p = root/name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('-- synthetic', encoding='utf-8')
            result, calls = self.flow(root)
            self.assertEqual(result['status'], 'completed')
            self.assertEqual(result['cleanup'], 'stopped')
            self.assertEqual(sum(c[0] == 'node' for c in calls), 1)
            self.assertEqual(sum(c[:2] == ['docker', 'stop'] for c in calls), 1)

    def test_cleanup_refuses_changed_ownership(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.FILES[:2]:
                p = root/name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('-- synthetic', encoding='utf-8')
            result, calls = self.flow(root, ownership_bad=True)
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['cleanup'], 'incomplete')
            self.assertFalse(any(c[:2] == ['docker', 'stop'] for c in calls))

    def test_failed_assertions_still_cleanup_and_running_container_fails(self):
        for options in ({'assertion_bad': True}, {'running': True}):
            with tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for name in m.FILES[:2]:
                    p = root/name
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text('-- synthetic', encoding='utf-8')
                result, calls = self.flow(root, **options)
                self.assertEqual(result['status'], 'failed')
                self.assertEqual(sum(c[0] == 'node' for c in calls), 1)
                self.assertTrue(any(c[:2] == ['docker', 'stop'] for c in calls))

    def test_static_scope_has_no_pull_remove_or_backend(self):
        source = Path(m.__file__).read_text(encoding='utf-8')
        for forbidden in ("'pull'", "'rm'", "'down'", "'--privileged'", "backend/dist/main.js"):
            self.assertNotIn(forbidden, source)
        self.assertIn("'127.0.0.1::5432'", source)
        self.assertIn('client.assert_owned(runtime, name, identity)', source)
        self.assertIn('client.Runtime(seconds=120)', source)


if __name__ == '__main__':
    unittest.main()
