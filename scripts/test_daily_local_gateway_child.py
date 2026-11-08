"""Private gateway child lifecycle with fake server; no certificate/socket access."""

import io
import json
import threading
import unittest
from daily_local_gateway_child import serve


class Server:
    def __init__(self):
        self.stopped = threading.Event()
        self.closed = False

    def serve_forever(self, poll_interval):
        self.stopped.wait(1)

    def shutdown(self):
        self.stopped.set()

    def server_close(self):
        self.closed = True

    def drain(self):
        pass


class GatewayChildTests(unittest.TestCase):
    def config(self):
        return json.dumps(dict(backend_port=29445, https_port=29443,
                               tls_cert='synthetic', tls_key='synthetic-key')).encode() + b'\n'

    def test_ready_and_eof_close(self):
        server, events = Server(), []
        serve(io.BytesIO(self.config()), events.append, lambda config: server)
        self.assertEqual(events, ['ASSET_DESK_READY'])
        self.assertTrue(server.closed)
        self.assertTrue(server.stopped.is_set())

    def test_bad_configuration_before_factory(self):
        for wire in (b'{}\n', b'x' * 16385, b'{}', b'{invalid}\n'):
            with self.assertRaises(ValueError):
                serve(io.BytesIO(wire), lambda event: None,
                      lambda config: self.fail('factory called'))

    def test_notification_failure_still_shuts_down(self):
        server = Server()
        def broken(event):
            raise RuntimeError('synthetic')
        with self.assertRaises(RuntimeError):
            serve(io.BytesIO(self.config()), broken, lambda config: server)
        self.assertTrue(server.closed)
