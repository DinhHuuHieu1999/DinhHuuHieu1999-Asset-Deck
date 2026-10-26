"""Offline category TLS orchestration contracts; no network or subprocess."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('category_tls_test', Path(__file__).with_name('category-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class CategoryHttpsTests(unittest.TestCase):
    def test_missing_source_refuses_before_shared_preflight(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for missing in m.FILES:
                for name in m.FILES:
                    p = root/name
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text('synthetic', encoding='utf-8')
                (root/missing).unlink()
                with patch.object(m.client, 'preflight') as shared:
                    with self.assertRaises(m.client.Refusal): m.preflight(root, SimpleNamespace())
                    shared.assert_not_called()

    @staticmethod
    def result():
        return dict(status='completed', syntheticOnly=True, categoryAcceptance=True, owners=2, matchingRecords=51)

    def test_exact_typed_result_required(self):
        m.validate_dart_result(self.result())
        for value in ({}, [], None, dict(self.result(), owners=True),
                      dict(self.result(), matchingRecords=50), dict(self.result(), extra=True)):
            with self.assertRaises(m.client.Refusal): m.validate_dart_result(value)

    def test_dto_failure_never_invokes_dart(self):
        class Runtime:
            def run(self, *args, **kwargs): raise AssertionError('Dart must not start')
        with patch.object(m, 'dto_acceptance', side_effect=m.client.Refusal('synthetic')):
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('.'), SimpleNamespace(), Runtime(), None, 'a'*32, None, None)

    def test_success_runs_dart_once_with_fixed_source_and_endpoint(self):
        calls = []
        class Runtime:
            def run(self, command, **kwargs):
                calls.append((command, kwargs))
                return json.dumps(CategoryHttpsTests.result()).encode()
        with patch.object(m, 'dto_acceptance') as dto:
            result = m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=59093),
                                  Runtime(), None, 'a'*32, None, None)
        self.assertTrue(result['categoryDartClient'])
        dto.assert_called_once()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], ['sdk.exe', '--disable-dart-dev',
            str(Path('source')/m.FILES[0]), '--synthetic-only', 'https://localhost:59093/api/v1', 'a'*32])

    def test_redirects_are_not_followed(self):
        self.assertIsNone(m.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.invalid'))


if __name__ == '__main__':
    unittest.main()
