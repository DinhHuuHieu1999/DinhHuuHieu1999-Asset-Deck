"""Offline sort HTTPS orchestration checks; never open sockets or subprocesses."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('sort_https_test', Path(__file__).with_name('check-sort-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class SortHttpsTests(unittest.TestCase):
    @staticmethod
    def result():
        return dict(status='completed', syntheticOnly=True, checkSortAcceptance=True,
                    owners=2, matchingRecords=56, listPaths=4, checkFilterCases=12)

    def test_fixed_check_profile_requires_schema_and_no_tls_bypass(self):
        source = Path(m.__file__).read_text(encoding='utf-8')
        self.assertIn('args.check_mode = True', source)
        self.assertNotIn('args.location_mode = True', source)
        self.assertIn('backend/migrations/006-asset-check.sql', m.FILES)
        self.assertEqual(len(m.FILES), len(set(m.FILES)))
        driver = Path(__file__).resolve().parent.parent/'flutter/tool/check_sort_https_acceptance.dart'
        self.assertNotIn('badCertificateCallback', driver.read_text(encoding='utf-8'))

    def test_exact_typed_result(self):
        m.validate_dart_result(self.result())
        for value in (None, [], {}, dict(self.result(), syntheticOnly=1),
                      dict(self.result(), owners=True), dict(self.result(), listPaths=2),
                      dict(self.result(), checkFilterCases=True), dict(self.result(), checkFilterCases=11), dict(self.result(), extra=True)):
            with self.assertRaises(m.client.Refusal):
                m.validate_dart_result(value)

    def test_missing_each_source_refuses_before_shared_preflight(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic', encoding='utf-8')
            for name in m.FILES:
                with self.subTest(name=name), patch.object(m.client, 'preflight') as shared:
                    path = root/name
                    path.unlink()
                    with self.assertRaises(m.client.Refusal): m.preflight(root, SimpleNamespace())
                    shared.assert_not_called()
                    path.write_text('synthetic', encoding='utf-8')

    def test_runs_once_and_calls_validation_before_real_client(self):
        calls = []
        class Runtime:
            def run(self, command, **kwargs):
                calls.append(command)
                return json.dumps(SortHttpsTests.result()).encode()
        with patch.object(m, 'dto_acceptance') as dto, patch.object(m, 'source_hashes', return_value={'source':'hash'}):
            result = m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=29443), Runtime(), None, 'a'*32, None, None)
            dto.assert_called_once()
        self.assertTrue(result['sortDartClient'])
        self.assertEqual(calls, [['sdk.exe', '--disable-dart-dev', str(Path('source')/m.FILES[0]), '--synthetic-only', 'https://localhost:29443/api/v1', 'a'*32]])

    def test_http_sort_queries_do_not_fail_due_to_unrelated_fields(self):
        requests = []
        identity = 'a'*32
        class Response:
            def __init__(self, status, body): self.status, self.body = status, body
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, size): return json.dumps(self.body).encode()
        class Opener:
            def open(self, request, timeout):
                parsed = m.urllib.parse.urlparse(request.full_url)
                query = m.urllib.parse.parse_qs(parsed.query)
                if parsed.path.startswith('/__asset_desk_fixture/'):
                    return Response(200, dict(fixtureId=identity, syntheticOnly=True))
                if parsed.path.endswith('/csrf-token'): return Response(200, dict(token='synthetic'))
                if parsed.path.endswith('/register'): return Response(201, dict(accessToken='synthetic'))
                requests.append((parsed.path, query))
                valid = query.get('sort') in (['name_asc'], ['updated_desc'], ['checked_asc']) and not any('[' in k for k in query)
                return Response(200 if valid else 400, dict(items=[], nextOffset=None))
        with patch.object(m.urllib.request, 'build_opener', return_value=Opener()):
            m.dto_acceptance(SimpleNamespace(tls_port=29443), SimpleNamespace(remaining=lambda: 120), identity)
        self.assertEqual(len(requests), 24)
        for path, query in requests:
            if path.endswith('/warranty'):
                self.assertEqual(query['warranty'], ['expiring_soon'])
                self.assertEqual(query['asOf'], ['2027-02-01'])
            else:
                self.assertNotIn('warranty', query)
                self.assertNotIn('asOf', query)
        self.assertEqual(set(path for path, _ in requests), {
            '/api/v1/assets', '/api/v1/assets/warranty', '/api/v1/assets/locations/inventory'})

    def test_source_changes_and_incomplete_results_fail_closed(self):
        class Runtime:
            def run(self, *args, **kwargs): return json.dumps(SortHttpsTests.result()).encode()
        with patch.object(m, 'dto_acceptance'), patch.object(m, 'source_hashes', side_effect=[{'source':'before'}, {'source':'after'}]):
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=29443), Runtime(), None, 'a'*32, None, None)


if __name__ == '__main__':
    unittest.main()
