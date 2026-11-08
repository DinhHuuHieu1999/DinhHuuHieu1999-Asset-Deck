"""Offline overview HTTPS orchestration; no network or real process invocation."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('overview_tls_test', Path(__file__).with_name('overview-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class OverviewHttpsTests(unittest.TestCase):
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
        return dict(status='completed', syntheticOnly=True, overviewAcceptance=True, owners=2, records=53)

    def test_exact_typed_output_required(self):
        m.validate_result(self.result())
        for value in ({}, [], None, dict(self.result(), owners=True),
                      dict(self.result(), records=52), dict(self.result(), extra=True)):
            with self.assertRaises(m.client.Refusal): m.validate_result(value)

    def test_driver_runs_once_with_fixed_source_and_endpoint(self):
        calls = []
        class Runtime:
            def run(self, command, **kwargs):
                calls.append((command, kwargs))
                return json.dumps(OverviewHttpsTests.result()).encode()
        result = m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)
        self.assertTrue(result['overviewDartClient'])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], ['sdk.exe', '--disable-dart-dev', str(Path('source')/m.FILES[0]),
            '--synthetic-only', 'https://localhost:59233/api/v1', 'a'*32])

    def test_safe_stage_failure_is_saved_but_never_passes(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{"status":"failed","stage":"empty-overview","secret":"not-retained"}'
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), Path(folder), 'a'*32, None, None)
            self.assertEqual(json.loads((Path(folder)/'overview-diagnostic.json').read_text()), {'status':'failed','stage':'empty-overview'})

    def test_incomplete_output_never_returns_success(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{}'
        with self.assertRaises(m.client.Refusal):
            m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)


if __name__ == '__main__':
    unittest.main()
