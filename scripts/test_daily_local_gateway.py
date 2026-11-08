"""Pure transport-policy tests; no TLS or sockets."""

import unittest
from daily_local_gateway import GatewayError, MAX_REQUEST, relay, validate_request


class GatewayTests(unittest.TestCase):
    def test_forwards_api_without_credentials_rewrite(self):
        calls = []
        def transport(*args):
            calls.append(args)
            return 200, [('Set-Cookie', 'a=1'), ('Set-Cookie', 'b=2')], b'{}'
        result = relay('GET', '/api/v1/assets?q=%25_',
                       [('Cookie', 'session=x')], b'', transport)
        self.assertEqual(calls[0][1], '/api/v1/assets?q=%25_')
        self.assertEqual(result[1], [('Set-Cookie', 'a=1'), ('Set-Cookie', 'b=2')])

    def test_hop_and_forwarding_headers_removed(self):
        headers = [('Connection', 'custom'), ('custom', 'remove'),
                   ('Host', 'attacker'), ('X-Forwarded-For', 'attacker'),
                   ('Forwarded', 'attacker'), ('Accept', 'application/json')]
        self.assertEqual(validate_request('GET', '/api/v1/assets', headers, b''),
                         [('Accept', 'application/json')])

    def test_invalid_targets_never_reach_transport(self):
        def forbidden(*args):
            self.fail('transport called')
        for target in ('https://host/api/v1/assets', '//host/api/v1/assets',
                       '/api/v1/../secret', '/api/v1/%2e%2e/secret',
                       '/api/v1/assets\r\nHost:evil', '/outside', '/api/v1//assets'):
            with self.assertRaises(GatewayError):
                relay('GET', target, [], b'', forbidden)

    def test_framing_rejected(self):
        for headers in ([('Content-Length', '2')],
                        [('Content-Length', '0'), ('Content-Length', '0')],
                        [('Transfer-Encoding', 'chunked')]):
            with self.assertRaises(GatewayError):
                validate_request('POST', '/api/v1/assets', headers, b'')

    def test_body_limit(self):
        with self.assertRaises(GatewayError):
            validate_request('POST', '/api/v1/assets', [], b'x' * (MAX_REQUEST + 1))

    def test_transport_error_redacted(self):
        def broken(*args):
            raise OSError('private-secret')
        with self.assertRaisesRegex(GatewayError, '^Upstream request failed$'):
            relay('GET', '/api/v1/assets', [], b'', broken)

    def test_bad_response_rejected(self):
        for result in ((101, [], b''), (200, [], 'not bytes'),
                       (200, [('X-Test', 'a\r\nb')], b'')):
            with self.assertRaises(GatewayError):
                relay('GET', '/api/v1/assets', [], b'', lambda *args: result)


if __name__ == '__main__':
    unittest.main()
