"""Offline export v2 HTTPS orchestration; no network or real process invocation."""
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('export_v2_tls_test', Path(__file__).with_name('export-v2-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class ExportV2HttpsTests(unittest.TestCase):
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
        return dict(status='completed', syntheticOnly=True, exportV2Acceptance=True, owners=2, assetCount=51, digest='python-sha256-stdin', nativeDialog='not-exercised')

    def test_exact_typed_output_required(self):
        m.validate_result(self.result())
        for value in ({}, [], None, dict(self.result(), owners=True),
                      dict(self.result(), assetCount=1), dict(self.result(), syntheticOnly=1),
                      dict(self.result(), exportV2Acceptance=1), dict(self.result(), extra=True)):
            with self.assertRaises(m.client.Refusal): m.validate_result(value)

    def test_driver_runs_once_with_fixed_source_and_endpoint(self):
        calls = []
        class Runtime:
            def run(self, command, **kwargs):
                calls.append((command, kwargs))
                return json.dumps(ExportV2HttpsTests.result()).encode()
        result = m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)
        self.assertTrue(result['exportV2DartClient'])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], ['sdk.exe', '--disable-dart-dev', str(Path('source')/m.FILES[0]),
            '--synthetic-only', 'https://localhost:59233/api/v1', 'a'*32, sys.executable])

    def test_safe_stage_failure_is_saved_but_never_passes(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{"status":"failed","stage":"export-v2","secret":"not-retained"}'
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), Path(folder), 'a'*32, None, None)
            self.assertEqual(json.loads((Path(folder)/'export-v2-diagnostic.json').read_text()), {'status':'failed','stage':'export-v2'})

    def test_incomplete_output_never_returns_success(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{}'
        with self.assertRaises(m.client.Refusal):
            m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)


class ExportV2ProfileTests(unittest.TestCase):
    def test_profile_is_explicit_typed_and_excludes_import(self):
        self.assertFalse(m.client.dates_mode(SimpleNamespace()))
        for value in ('true', 1, None):
            with self.assertRaises(m.client.Refusal):
                m.client.fixture_files(SimpleNamespace(dates_mode=value))
        with self.assertRaises(m.client.Refusal):
            m.client.fixture_files(SimpleNamespace(dates_mode=True, import_mode=True))
        files = m.client.fixture_files(SimpleNamespace(dates_mode=True))
        self.assertIn('backend/migrations/004-asset-dates.sql', files)
        self.assertNotIn('backend/migrations/003-asset-import.sql', files)


if __name__ == '__main__':
    unittest.main()
