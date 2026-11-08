"""Listener construction tests without sockets or real certificates."""

import unittest
import io
from unittest.mock import patch
from daily_local_https import create_server, make_handler, BoundedServer
import threading


class Context:
    def __init__(self, protocol):
        self.loaded = False

    def load_cert_chain(self, *args):
        self.loaded = True

    def wrap_socket(self, sock, **kwargs):
        if kwargs != {'server_side': True, 'do_handshake_on_connect': False}:
            raise AssertionError('Unbounded accept handshake')
        return sock


class Server:
    def __init__(self, address, handler, bind_and_activate):
        self.address, self.handler = address, handler
        self.socket = object()
        self.closed = False
        assert bind_and_activate is False

    def server_bind(self):
        pass

    def server_activate(self):
        pass

    def server_close(self):
        self.closed = True


class HttpsTests(unittest.TestCase):
    def setUp(self):
        self.config = dict(backend_port=29445, https_port=29443,
                           tls_cert='synthetic-cert', tls_key='synthetic-key')

    def test_loopback_and_no_default_request_logging(self):
        server = create_server(self.config, Context, Server, lambda port: None)
        self.assertEqual(server.address, ('127.0.0.1', 29443))
        self.assertEqual(server.handler.protocol_version, 'HTTP/1.0')
        self.assertFalse(server.closed)

    def test_invalid_ports_before_tls(self):
        def forbidden(*args):
            self.fail('TLS accessed')
        self.config['https_port'] = self.config['backend_port']
        with self.assertRaises(ValueError):
            create_server(self.config, forbidden)

    def test_bind_failure_closes_server(self):
        instances = []
        class Broken(Server):
            def server_bind(self):
                instances.append(self)
                raise OSError('private-path')
        with self.assertRaisesRegex(RuntimeError, '^HTTPS listener initialization failed$'):
            create_server(self.config, Context, Broken, lambda port: None)
        self.assertTrue(instances[0].closed)

    def test_drain_is_bounded_without_network(self):
        server = BoundedServer.__new__(BoundedServer)
        server.drained = threading.Condition()
        server.active = 0
        server.drain(0)
        server.active = 1
        with self.assertRaisesRegex(RuntimeError, 'deadline'):
            server.drain(0)


class MemorySocket:
    def __init__(self, wire):
        self.input = io.BytesIO(wire)
        self.output = bytearray()

    def settimeout(self, timeout):
        pass

    def do_handshake(self):
        pass

    def makefile(self, mode, *args):
        return self.input

    def sendall(self, data):
        self.output.extend(data)


class InertTimer:
    def __init__(self, *args):
        pass

    def start(self):
        pass

    def cancel(self):
        pass


class WireTests(unittest.TestCase):
    def request(self, wire, result=(200, [('Content-Type', 'application/json')], b'{}')):
        self.calls = []
        def transport(*args):
            self.calls.append(args)
            return result
        sock = MemorySocket(wire)
        class LocalServer:
            server_port = 29443
        with patch('daily_local_https.threading.Timer', InertTimer):
            make_handler(transport)(sock, ('127.0.0.1', 12345), LocalServer())
        return bytes(sock.output)

    def test_get_and_repeated_cookies(self):
        wire = self.request(b'GET /api/v1/assets HTTP/1.1\r\nHost: localhost:29443\r\n\r\n',
                            (200, [('Set-Cookie', 'a=1'), ('Set-Cookie', 'b=2')], b'{}'))
        self.assertIn(b'200 OK', wire)
        self.assertEqual(wire.count(b'Set-Cookie:'), 2)
        self.assertTrue(wire.endswith(b'\r\n\r\n{}'))

    def test_post_body_is_forwarded_once(self):
        self.request(b'POST /api/v1/assets HTTP/1.1\r\nHost: localhost:29443\r\nContent-Length: 2\r\n\r\n{}')
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0][3], b'{}')

    def test_duplicate_length_rejected_before_transport(self):
        wire = self.request(b'POST /api/v1/assets HTTP/1.1\r\nHost: localhost:29443\r\nContent-Length: 0\r\n'
                            b'Content-Length: 0\r\n\r\n')
        self.assertIn(b'502 Bad Gateway', wire)
        self.assertEqual(self.calls, [])

    def test_oversized_body_rejected_without_read(self):
        wire = self.request(b'POST /api/v1/assets HTTP/1.1\r\n'
                            b'Host: localhost:29443\r\nContent-Length: 2097153\r\n\r\n')
        self.assertIn(b'413', wire)
        self.assertEqual(self.calls, [])

    def test_chunked_and_expect_rejected(self):
        for header in (b'Transfer-Encoding: chunked', b'Expect: 100-continue'):
            wire = self.request(b'POST /api/v1/assets HTTP/1.1\r\nHost: localhost:29443\r\n' + header + b'\r\n\r\n')
            self.assertNotIn(b'200 OK', wire)
            self.assertEqual(self.calls, [])

    def test_invalid_target_does_not_echo(self):
        wire = self.request(b'GET /private-secret HTTP/1.1\r\nHost: localhost:29443\r\n\r\n')
        self.assertNotIn(b'private-secret', wire)
        self.assertEqual(self.calls, [])

    def test_unknown_method_no_reflection(self):
        wire = self.request(b'SECRET /api/v1/assets HTTP/1.1\r\n\r\n')
        self.assertIn(b'501', wire)
        self.assertNotIn(b'SECRET', wire)
        self.assertEqual(self.calls, [])

    def test_head_suppresses_body(self):
        wire = self.request(b'HEAD /api/v1/assets HTTP/1.1\r\nHost: localhost:29443\r\n\r\n')
        self.assertIn(b'200 OK', wire)
        self.assertEqual(len(self.calls), 1)
        self.assertTrue(wire.endswith(b'\r\n\r\n'))

    def test_pipeline_only_first_request_processed(self):
        wire = b'GET /api/v1/assets HTTP/1.1\r\nHost: localhost:29443\r\n\r\n'
        self.request(wire + wire)
        self.assertEqual(len(self.calls), 1)

    def test_untrusted_missing_duplicate_host_rejected(self):
        for headers in (b'', b'Host: evil.invalid\r\n',
                        b'Host: localhost:29443\r\nHost: localhost:29443\r\n',
                        b'Host: localhost:8180\r\n'):
            wire = self.request(b'GET /api/v1/assets HTTP/1.1\r\n' + headers + b'\r\n')
            self.assertIn(b'400', wire)
            self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
