"""HTTPS client assertions with fake responses; never connect or load TLS material."""

import io
import json
import unittest
from unittest.mock import patch
from daily_local_fixture_client import SyntheticClient


class Response(io.BytesIO):
    status = 200


class Opener:
    def __init__(self): self.calls = []
    def open(self, request, timeout):
        self.calls.append((request, timeout))
        return Response(b'{}')


class ClientTests(unittest.TestCase):
    def test_fixed_https_and_timeout(self):
        opener = Opener()
        client = SyntheticClient(29443, lambda: 3, opener)
        self.assertEqual(client.request('/api/v1/assets'), {})
        request, timeout = opener.calls[0]
        self.assertEqual(request.full_url, 'https://localhost:29443/api/v1/assets')
        self.assertEqual(timeout, 3)

    def test_redirect_target_path_refused_before_transport(self):
        opener = Opener()
        client = SyntheticClient(29443, lambda: 3, opener)
        with self.assertRaises(ValueError): client.request('https://foreign.invalid/')
        self.assertEqual(opener.calls, [])

    def test_create_and_login_compare_record_not_only_count(self):
        client = SyntheticClient(29443, lambda: 3, Opener())
        calls = []
        def request(path, data=None, expected=200):
            calls.append(path)
            if path.endswith('/auth/login'):
                self.assertEqual(data, {'identifier': client.account['email'],
                                        'password': client.account['password']})
            if path.endswith('csrf-token'): return {'token': 'synthetic'}
            if '/auth/' in path: return {'accessToken': 'synthetic'}
            if data: return dict(client.asset, id='asset-id')
            return {'items': [dict(client.asset, id='asset-id')]}
        client.request = request
        asset_id = client.create_synthetic_asset()
        client.login_and_assert_asset(asset_id)
        self.assertIn('/api/v1/auth/login', calls)
        with self.assertRaises(RuntimeError): client.login_and_assert_asset('wrong-id')

    def test_raw_host_cases_use_default_tls_and_no_redirect(self):
        instances = []
        class Connection:
            def __init__(self, host, port, **kwargs):
                self.headers, self.closed = [], False
                instances.append(self)
            def putrequest(self, method, target, **kwargs):
                assert kwargs['skip_host'] is True
            def putheader(self, name, value): self.headers.append((name, value))
            def endheaders(self): pass
            def getresponse(self):
                response = Response(b'')
                response.status = 400
                return response
            def close(self): self.closed = True
        client = SyntheticClient(29443, lambda: 3, Opener())
        with patch('daily_local_fixture_client.ssl.create_default_context', return_value=object()), \
             patch('daily_local_fixture_client.http.client.HTTPSConnection', Connection):
            client.assert_invalid_requests_rejected()
        self.assertEqual([len(c.headers) for c in instances], [0, 1, 2])
        self.assertTrue(all(c.closed for c in instances))
