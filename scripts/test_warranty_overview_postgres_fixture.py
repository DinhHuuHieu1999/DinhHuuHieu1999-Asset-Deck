"""Offline warranty-profile checks; all Docker/process commands are synthetic."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import time
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('warranty_fixture_test', Path(__file__).with_name('warranty-overview-postgres-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)
r = m.repository


class WarrantyFixtureTests(unittest.TestCase):
    def test_exact_seven_results_required(self):
        valid = dict(success=True, numPassedTests=7, numTotalTests=7,
                     numFailedTests=0, numPendingTests=0,
                     numRuntimeErrorTestSuites=0, numPassedTestSuites=1)
        r.validate_result(valid, 7)
        for field, value in [('numPassedTests', 4), ('numTotalTests', 8),
                             ('numPendingTests', 1), ('success', False)]:
            with self.subTest(field=field), self.assertRaises(r.client.Refusal):
                r.validate_result(dict(valid, **{field: value}), 7)

    def test_unknown_profile_never_runs_a_command(self):
        with patch.object(r.client.Runtime, 'run') as run:
            with self.assertRaises(r.client.Refusal):
                r.execute(Path('.'), SimpleNamespace(), r.client.Runtime(), profile='arbitrary')
            run.assert_not_called()

    def test_missing_each_warranty_file_refuses_before_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in r.WARRANTY_OVERVIEW_FILES:
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            for name in r.WARRANTY_OVERVIEW_FILES:
                target = root/name
                target.unlink()
                with patch.object(r.client.Runtime, 'run') as run:
                    with self.assertRaises(r.client.Refusal):
                        r.execute(root, SimpleNamespace(execute_synthetic=True, image='sha256:'+'b'*64), r.client.Runtime(), profile='warranty-overview')
                    run.assert_not_called()
                target.write_text('synthetic', encoding='utf-8')

    def test_mocked_profile_has_exact_suite_identity_env_and_stops(self):
        calls = []
        identity = 'a'*32
        class Runtime:
            env = {}
            deadline = time.monotonic()+120
            def run(self, command, **kwargs):
                calls.append((command, kwargs))
                if command[:3] == ['docker', 'image', 'inspect']:
                    return ('sha256:'+'b'*64).encode()
                if command[:2] == ['docker', 'inspect']:
                    if '.Config.Labels' in command[3]:
                        return json.dumps({r.client.LABEL: identity}).encode()
                    if '.State.Running' in command[3]: return b'false'
                    return json.dumps({'5432/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '59201'}]}).encode()
                if command[:2] == ['docker', 'exec'] and '-Atqc' in command:
                    return ('asset_warranty_overview_fixture_'+identity[:12]+'|fixture').encode()
                if command[0] == 'node':
                    env = kwargs['env']
                    assert env['ASSET_WARRANTY_OVERVIEW_FIXTURE_OPT_IN'] == 'isolated-warranty-overview-v1'
                    assert env['ASSET_WARRANTY_OVERVIEW_FIXTURE_MARKER'] == identity
                    assert 'ASSET_CATEGORY_FIXTURE_OPT_IN' not in env
                    assert command[4].endswith('assets-warranty-overview.postgres.spec.ts')
                    destination = next(v.split('=',1)[1] for v in command if v.startswith('--outputFile='))
                    Path(destination).write_text(json.dumps(dict(success=True, numPassedTests=7, numTotalTests=7,
                        numFailedTests=0, numPendingTests=0, numRuntimeErrorTestSuites=0, numPassedTestSuites=1)), encoding='utf-8')
                return b''
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in r.WARRANTY_OVERVIEW_FILES:
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            with patch.object(r, 'preflight'), patch.object(r.secrets, 'token_hex', return_value=identity):
                result = r.execute(root, SimpleNamespace(image='sha256:'+'b'*64), Runtime(), profile='warranty-overview')
            self.assertEqual(result['status'], 'completed')
            self.assertEqual(result['cleanup'], 'stopped')
            self.assertEqual(sum(c[0][0] == 'node' for c in calls), 1)
            self.assertEqual(sum(c[0][:2] == ['docker','stop'] for c in calls), 1)
            marker_sql = [kw['data'] for cmd,kw in calls if 'data' in kw][-1]
            self.assertIn(b'asset_warranty_overview_fixture_identity', marker_sql)
            self.assertNotIn(b'asset_category_fixture_identity', marker_sql)
            migrations = [kw['data'] for cmd, kw in calls if cmd[:3] == ['docker', 'exec', '-i'] and 'data' in kw]
            self.assertEqual(len(migrations), 4)
            self.assertEqual(migrations[2], b'synthetic')

    def test_wrapper_dispatches_fixed_profile_once_and_refuses_without_opt_in(self):
        with patch('sys.argv', ['warranty-overview-postgres-fixture.py']), patch.object(r, 'execute', side_effect=r.client.Refusal('opt in')) as execute:
            self.assertEqual(m.main(), 1)
            self.assertEqual(execute.call_count, 1)
            self.assertEqual(execute.call_args.kwargs['profile'], 'warranty-overview')
            self.assertFalse(execute.call_args.args[1].execute_synthetic)


if __name__ == '__main__':
    unittest.main()
