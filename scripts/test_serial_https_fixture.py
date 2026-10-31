"""Offline serial HTTPS orchestration checks; never open sockets or subprocesses."""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('serial_https_test', Path(__file__).with_name('serial-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class SerialHttpsTests(unittest.TestCase):
    @staticmethod
    def result():
        return dict(status='completed', syntheticOnly=True, serialAcceptance=True,
                    owners=2, readOnlySnapshots=2)

    def test_exact_typed_result(self):
        m.validate_dart_result(self.result())
        for value in (None, [], {}, dict(self.result(), syntheticOnly=1),
                      dict(self.result(), owners=True), dict(self.result(), readOnlySnapshots=1),
                      dict(self.result(), extra=True)):
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
                return json.dumps(SerialHttpsTests.result()).encode()
        with patch.object(m, 'dto_acceptance') as dto, patch.object(m, 'source_hashes', return_value={'source':'hash'}):
            result = m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=29443), Runtime(), None, 'a'*32, None, None)
            dto.assert_called_once()
        self.assertTrue(result['serialDartClient'])
        self.assertEqual(calls, [['sdk.exe', '--disable-dart-dev', str(Path('source')/m.FILES[0]), '--synthetic-only', 'https://localhost:29443/api/v1', 'a'*32]])

    def test_source_change_refuses_after_driver(self):
        class Runtime:
            def run(self, command, **kwargs):
                return json.dumps(SerialHttpsTests.result()).encode()
        with patch.object(m, 'dto_acceptance'), patch.object(m, 'source_hashes', side_effect=[{'x':'a'}, {'x':'b'}]):
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('source'), SimpleNamespace(dart='sdk', tls_port=29443), Runtime(), None, 'a'*32, None, None)

    def test_redirects_are_never_followed(self):
        self.assertIsNone(m.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.invalid'))

    def test_http_validation_and_cache_fail_closed(self):
        identity = 'a'*32
        requests = []
        class Response:
            def __init__(self, status, body, cache='no-store'):
                self.status, self.body, self.headers = status, body, {'Cache-Control':cache}
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, size): return json.dumps(self.body).encode()
        class Opener:
            cache = 'no-store'
            def open(self, request, timeout):
                parsed = m.urllib.parse.urlparse(request.full_url)
                if parsed.path.startswith('/__asset_desk_fixture/'):
                    return Response(200, dict(fixtureId=identity, syntheticOnly=True))
                if parsed.path.endswith('/csrf-token'): return Response(200, dict(token='synthetic'))
                if parsed.path.endswith('/register'): return Response(201, dict(accessToken='synthetic'))
                requests.append(request)
                if not request.has_header('Authorization'): return Response(401, {})
                q = m.urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
                invalid = ('serial[nested]' in q or len(q.get('serial', [])) != 1 or
                           len(q.get('serial', [''])[0]) > 120 or
                           '\x00' in q.get('serial', [''])[0] or 'excludeId' in q)
                return Response(400 if invalid else 200, dict(duplicate=False), self.cache)
        opener = Opener()
        with patch.object(m.urllib.request, 'build_opener', return_value=opener):
            m.dto_acceptance(SimpleNamespace(tls_port=29443), SimpleNamespace(remaining=lambda:120), identity)
            self.assertEqual(len(requests), 10)
            opener.cache = 'public'
            with self.assertRaises(m.client.Refusal):
                m.dto_acceptance(SimpleNamespace(tls_port=29443), SimpleNamespace(remaining=lambda:120), identity)


if __name__ == '__main__':
    unittest.main()
