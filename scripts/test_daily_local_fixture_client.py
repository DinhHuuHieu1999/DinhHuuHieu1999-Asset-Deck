"""HTTPS client assertions with fake responses; never connect or load TLS material."""

import io
import json
import unittest
from unittest.mock import Mock, patch
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


class MethodTests(unittest.TestCase):
    def test_put_uses_same_fixed_https_transport_and_csrf(self):
        opener = Opener()
        client = SyntheticClient(29443, lambda: 3, opener)
        client.csrf = 'synthetic-csrf'
        client.request('/api/v1/assets/synthetic/location', {'location': None}, method='PUT')
        request, _ = opener.calls[0]
        self.assertEqual(request.get_method(), 'PUT')
        self.assertEqual(request.get_header('X-csrf-token'), 'synthetic-csrf')
        self.assertEqual(json.loads(request.data), {'location': None})

    def test_arbitrary_method_refused_before_transport(self):
        opener = Opener()
        client = SyntheticClient(29443, lambda: 3, opener)
        with self.assertRaises(ValueError):
            client.request('/api/v1/assets', method='CONNECT')
        self.assertEqual(opener.calls, [])


class TimingTests(unittest.TestCase):
    def test_timing_is_redacted_and_bounded(self):
        client = SyntheticClient(29443, lambda: 3, Opener())
        with patch('daily_local_fixture_client.time.monotonic', side_effect=[1, 3]):
            client.request('/api/v1/assets/private-id')
        self.assertEqual(client.request_timings,
                         [dict(elapsedSeconds=2, outcome='completed')])
        client.request_timings = [{}] * 256
        client.request('/api/v1/assets')
        self.assertEqual(len(client.request_timings), 256)

    def test_transport_failure_retains_timing_without_error_text(self):
        opener = Opener()
        opener.open = lambda *args, **kwargs: (_ for _ in ()).throw(OSError('private'))
        client = SyntheticClient(29443, lambda: 3, opener)
        with self.assertRaises(OSError): client.request('/api/v1/assets')
        self.assertEqual(client.request_timings[0]['outcome'], 'transport-error')
        self.assertNotIn('private', repr(client.request_timings))

    def test_response_failure_is_not_completed(self):
        client = SyntheticClient(29443, lambda: 3, Opener())
        with self.assertRaises(RuntimeError):
            client.request('/api/v1/assets', expected=201)
        self.assertEqual(client.request_timings[0]['outcome'], 'response-mismatch')


class LoopbackTransportTests(unittest.TestCase):
    def test_ipv4_socket_retains_localhost_sni_and_verification(self):
        import ssl
        from daily_local_fixture_client import LoopbackHTTPSConnection
        context = ssl.create_default_context()
        self.assertTrue(context.check_hostname)
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
        connection = LoopbackHTTPSConnection('localhost', 29443, timeout=3, context=context)
        raw_socket = Mock()
        with patch('daily_local_fixture_client.socket.create_connection', return_value=raw_socket) as create, \
             patch.object(context, 'wrap_socket', return_value=object()) as wrap:
            connection.connect()
        create.assert_called_once_with(('127.0.0.1', 29443), 3, None)
        wrap.assert_called_once_with(raw_socket, server_hostname='localhost')
        self.assertTrue(context.check_hostname)
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)

    def test_non_localhost_refused_without_socket(self):
        from daily_local_fixture_client import LoopbackHTTPSConnection
        with patch('daily_local_fixture_client.socket.create_connection') as create:
            with self.assertRaises(ValueError): LoopbackHTTPSConnection('foreign.invalid', 29443)
            with self.assertRaises(ValueError):
                LoopbackHTTPSConnection._connect_ipv4(('foreign.invalid', 29443), 3)
        create.assert_not_called()

    def test_handler_uses_scoped_connection_and_existing_context(self):
        from daily_local_fixture_client import LoopbackHTTPSConnection, LoopbackHTTPSHandler
        import ssl
        context = ssl.create_default_context()
        handler = LoopbackHTTPSHandler(context=context)
        request = object()
        with patch.object(handler, 'do_open', return_value='response') as open_request:
            self.assertEqual(handler.https_open(request), 'response')
        open_request.assert_called_once_with(LoopbackHTTPSConnection, request, context=context)
