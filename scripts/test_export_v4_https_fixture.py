"""Offline export v2 HTTPS orchestration; no network or real process invocation."""
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('export_v4_tls_test', Path(__file__).with_name('export-v4-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class ExportV4HttpsTests(unittest.TestCase):
    def test_missing_each_source_refuses_before_shared_preflight(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.FILES:
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            for name in m.FILES:
                target = root/name
                target.unlink()
                with patch.object(m.client, 'preflight') as shared:
                    with self.assertRaises(m.client.Refusal): m.preflight(root, SimpleNamespace())
                    shared.assert_not_called()
                target.write_text('synthetic', encoding='utf-8')

    @staticmethod
    def result():
        return dict(status='completed', syntheticOnly=True, exportV4Acceptance=True, owners=2, assetCount=51, digest='python-sha256-stdin', nativeDialog='not-exercised')

    def test_exact_typed_output_required(self):
        m.validate_result(self.result())
        for value in ({}, [], None, dict(self.result(), owners=True),
                      dict(self.result(), assetCount=1), dict(self.result(), syntheticOnly=1),
                      dict(self.result(), exportV4Acceptance=1), dict(self.result(), extra=True)):
            with self.assertRaises(m.client.Refusal): m.validate_result(value)

    def test_driver_runs_once_with_fixed_source_and_endpoint(self):
        calls = []
        class Runtime:
            def run(self, command, **kwargs):
                calls.append((command, kwargs))
                return json.dumps(ExportV4HttpsTests.result()).encode()
        result = m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)
        self.assertTrue(result['exportV4DartClient'])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], ['sdk.exe', '--disable-dart-dev', str(Path('source')/m.FILES[0]),
            '--synthetic-only', 'https://localhost:59233/api/v1', 'a'*32, sys.executable])

    def test_safe_stage_failure_is_saved_but_never_passes(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{"status":"failed","stage":"export-v4","secret":"not-retained"}'
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), Path(folder), 'a'*32, None, None)
            self.assertEqual(json.loads((Path(folder)/'export-v4-diagnostic.json').read_text()), {'status':'failed','stage':'export-v4'})

    def test_incomplete_output_never_returns_success(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{}'
        with self.assertRaises(m.client.Refusal):
            m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)


class ExportV4ProfileTests(unittest.TestCase):
    def test_profile_is_exclusive_and_requires_all_v4_artifacts(self):
        self.assertFalse(m.client.export_v4_mode(SimpleNamespace()))
        for value in ('true', 1, None):
            with self.assertRaises(m.client.Refusal):
                m.client.fixture_files(SimpleNamespace(export_v4_mode=value))
        for flag in ('import_mode', 'dates_mode', 'import_v2_mode', 'location_mode', 'export_v3_mode', 'import_v3_mode', 'selection_export_mode', 'selection_export_v2_mode', 'check_mode'):
            with self.assertRaises(m.client.Refusal):
                m.client.fixture_files(SimpleNamespace(export_v4_mode=True, **{flag: True}))
        files = m.client.fixture_files(SimpleNamespace(export_v4_mode=True))
        for name in ('backend/migrations/004-asset-dates.sql', 'backend/migrations/005-asset-location.sql',
                     'backend/dist/domains/assets/asset-export-v4.module.js',
                     'backend/dist/domains/assets/asset-export-v4.repository.js',
                     'backend/dist/domains/assets/asset-check.module.js'):
            self.assertIn(name, files)
        self.assertIn('backend/migrations/006-asset-check.sql', files)
        self.assertNotIn('backend/dist/domains/assets/asset-export-v4.module.js', m.client.fixture_files(SimpleNamespace(location_mode=True)))


    def test_v4_lifecycle_wires_only_fixed_flags_and_stops(self):
        base_spec = importlib.util.spec_from_file_location('v4_shared_fake', Path(__file__).with_name('test_client_https_fixture.py'))
        base = importlib.util.module_from_spec(base_spec)
        base_spec.loader.exec_module(base)
        starts = []
        class Runtime(base.FakeRuntime):
            def start(self, command, cwd, env=None):
                starts.append((command, env))
                return super().start(command, cwd, env)
        runtime = Runtime()
        args = base.arguments()
        args.export_v4_mode = True
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.client.fixture_files(args):
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            with patch.object(m.client, 'preflight'), patch.object(m.client.subprocess, 'run', side_effect=AssertionError('No real process')), patch.object(m.client.subprocess, 'Popen', side_effect=AssertionError('No real process')):
                result = m.client.execute(root, args, runtime, lambda *unused: dict(status='completed', syntheticOnly=True))
            self.assertEqual(result['cleanup'], 'stopped')
            self.assertTrue(runtime.stopped)
            backend = next(env for command, env in starts if env is not None)
            for key in ('ASSET_EXPORT_V4_ENABLED', 'ASSET_EXPORT_V3_ENABLED', 'ASSET_CHECK_ENABLED', 'ASSET_DATES_ENABLED', 'ASSET_LOCATION_ENABLED'):
                self.assertEqual(backend[key], 'true')
            for key in ('ASSET_SELECTION_EXPORT_ENABLED', 'ASSET_SELECTION_EXPORT_V2_ENABLED', 'ASSET_IMPORT_V2_ENABLED', 'ASSET_IMPORT_V3_ENABLED'):
                self.assertEqual(backend[key], 'false')
            self.assertEqual(sum('--export-v4-enabled' in command for command, _ in starts), 1)
            self.assertEqual(sum(c[:2] == ['docker', 'stop'] for c in runtime.calls), 1)


if __name__ == '__main__':
    unittest.main()
