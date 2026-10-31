"""Offline inventory details lifecycle contracts; no Docker or database execution."""
import importlib.util
import json
import time
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('details_lifecycle_test', Path(__file__).with_name('details-postgres-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)
r = m.repository


class DetailsFixtureTests(unittest.TestCase):
    def test_fixed_profile_and_four_assertions(self):
        files, prefix, database, env, opt_in, table = r.profile_settings('details')
        self.assertEqual((prefix, database, env, opt_in, table), (
            'asset-details-', 'asset_details_fixture_', 'ASSET_DETAILS',
            'isolated-details-v1', 'asset_details_fixture_identity'))
        self.assertEqual(files[2], 'backend/src/domains/assets/asset-details.postgres.spec.ts')
        self.assertIn('backend/src/domains/assets/asset-sort.ts', files)
        self.assertNotIn('backend/migrations/004-asset-dates.sql', files)
        self.assertNotIn('backend/migrations/005-asset-location.sql', files)
        self.assertEqual(len(files), len(set(files)))

    def test_no_opt_in_has_no_side_effect(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(r.client.Runtime, 'run') as run:
            with self.assertRaises(r.client.Refusal):
                r.execute(Path(folder), SimpleNamespace(execute_synthetic=False, image='sha256:' + 'a'*64), r.client.Runtime(), profile='details')
            run.assert_not_called()
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_every_required_file_is_checked_before_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in r.DETAILS_FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic', encoding='utf-8')
            for name in r.DETAILS_FILES:
                with self.subTest(name=name), patch.object(r.client.Runtime, 'run') as run:
                    path = root/name
                    path.unlink()
                    with self.assertRaises(r.client.Refusal):
                        r.execute(root, SimpleNamespace(execute_synthetic=True, image='sha256:'+'a'*64), r.client.Runtime(), profile='details')
                    run.assert_not_called()
                    self.assertFalse((root/'.local').exists())
                    path.write_text('synthetic', encoding='utf-8')

    def test_mocked_lifecycle_runs_exact_suite_and_preserves_cleanup_boundary(self):
        identity = 'a' * 32
        for bad_owner, incomplete in ((False, False), (True, False), (False, True)):
            with self.subTest(bad_owner=bad_owner, incomplete=incomplete), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                for name in r.DETAILS_FILES[:2]:
                    path = root/name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('-- synthetic', encoding='utf-8')
                calls = []
                class Runtime:
                    env = {}
                    deadline = time.monotonic() + 120
                    def run(self, command, **kwargs):
                        calls.append(command)
                        if command[:3] == ['docker', 'image', 'inspect']:
                            return ('sha256:' + 'b'*64).encode()
                        if command[:2] == ['docker', 'inspect']:
                            if '.Config.Labels' in command[3]:
                                count = sum(c[:2] == ['docker', 'inspect'] and '.Config.Labels' in c[3] for c in calls)
                                return json.dumps({r.client.LABEL: 'wrong' if bad_owner and count >= 3 else identity}).encode()
                            if '.State.Running' in command[3]:
                                return b'false'
                            return json.dumps({'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '59091'}]}).encode()
                        if command[:2] == ['docker', 'exec'] and '-Atqc' in command:
                            return ('asset_details_fixture_' + identity[:12] + '|fixture').encode()
                        if command[0] == 'node':
                            self_test_env = kwargs['env']
                            if self_test_env.get('ASSET_DETAILS_FIXTURE_OPT_IN') != 'isolated-details-v1':
                                raise AssertionError('wrong opt-in')
                            result = dict(success=True, numPassedTests=3 if incomplete else 4, numTotalTests=4,
                                          numFailedTests=0, numPendingTests=0, numRuntimeErrorTestSuites=0, numPassedTestSuites=1)
                            target = next(c.split('=', 1)[1] for c in command if c.startswith('--outputFile='))
                            Path(target).write_text(json.dumps(result), encoding='utf-8')
                        return b''
                with patch.object(r, 'preflight'), patch.object(r.secrets, 'token_hex', return_value=identity):
                    if bad_owner or incomplete:
                        with self.assertRaises(r.client.Refusal):
                            r.execute(root, SimpleNamespace(image='sha256:'+'b'*64), Runtime(), profile='details')
                    else:
                        result = r.execute(root, SimpleNamespace(image='sha256:'+'b'*64), Runtime(), profile='details')
                        self.assertEqual(result['repositoryTests'], 4)
                        self.assertEqual(result['cleanup'], 'stopped')
                self.assertEqual(sum(c[0] == 'node' for c in calls), 1)
                self.assertEqual(sum(c[:2] == ['docker', 'stop'] for c in calls), 0 if bad_owner else 1)
                node = next(c for c in calls if c[0] == 'node')
                self.assertIn(str(root/'backend/src/domains/assets/asset-details.postgres.spec.ts'), node)
                self.assertFalse(any(c[:2] in (['docker', 'pull'], ['docker', 'rm']) for c in calls))

    def test_wrapper_is_fixed_and_bounded(self):
        source = Path(m.__file__).read_text(encoding='utf-8')
        self.assertIn("profile='details'", source)
        self.assertIn('Runtime(seconds=120)', source)
        self.assertNotIn('add_argument(\'--profile', source)


if __name__ == '__main__':
    unittest.main()
