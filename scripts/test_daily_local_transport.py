"""Transport tests use fake connections and timers, never real sockets."""

import unittest
from daily_local_transport import loopback_transport


class Timer:
    def __init__(self, timeout, callback):
        self.callback = callback
        self.cancelled = False

    def start(self):
        pass

    def cancel(self):
        self.cancelled = True


class Connection:
    def __init__(self, host, port, timeout):
        self.host, self.port = host, port
        self.sock = None
        self.status = 302
        self.chunks = [b'ok', b'']
        self.closed = False
        self.headers = []

    def connect(self):
        pass

    def putrequest(self, *args, **kwargs):
        self.request = args

    def putheader(self, name, value):
        self.headers.append((name, value))

    def endheaders(self, body):
        pass

    def getresponse(self):
        return self

    def getheaders(self):
        return [('Location', 'https://not-followed.invalid/')]

    def read1(self, count):
        return self.chunks.pop(0)

    def close(self):
        self.closed = True


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.connections, self.timers = [], []

    def connection(self, *args, **kwargs):
        result = Connection(*args, **kwargs)
        self.connections.append(result)
        return result

    def timer(self, *args):
        result = Timer(*args)
        self.timers.append(result)
        return result

    def test_fixed_host_no_redirect_and_cleanup(self):
        transport = loopback_transport(29445, self.connection, self.timer)
        status, _, body = transport('GET', '/api/v1/assets', [], b'', 1, 10)
        self.assertEqual((status, body), (302, b'ok'))
        self.assertEqual(len(self.connections), 1)
        self.assertEqual(self.connections[0].host, '127.0.0.1')
        self.assertTrue(self.connections[0].closed)
        self.assertTrue(self.timers[0].cancelled)
        self.assertEqual(self.connections[0].auto_open, 0)

    def test_size_failure_closes(self):
        transport = loopback_transport(29445, self.connection, self.timer)
        with self.assertRaises(ValueError):
            transport('GET', '/api/v1/assets', [], b'', 1, 1)
        self.assertTrue(self.connections[0].closed)

    def test_deadline_before_request(self):
        values = iter([0, 2])
        transport = loopback_transport(29445, self.connection, self.timer,
                                       clock=lambda: next(values))
        with self.assertRaises(TimeoutError):
            transport('GET', '/api/v1/assets', [], b'', 1, 10)
        self.assertFalse(hasattr(self.connections[0], 'request'))
        self.assertTrue(self.connections[0].closed)

    def test_watchdog_aborts_before_request(self):
        class Expired(Timer):
            def start(self):
                self.callback()
        transport = loopback_transport(29445, self.connection, Expired)
        with self.assertRaises(TimeoutError):
            transport('GET', '/api/v1/assets', [], b'', 1, 10)
        self.assertTrue(self.connections[0].closed)

    def test_invalid_bounds_do_not_construct_connection(self):
        transport = loopback_transport(29445, self.connection, self.timer)
        for timeout, limit in ((True, 1), (0, 1), (31, 1), (1, 0), (1, True)):
            with self.assertRaises(ValueError):
                transport('GET', '/api/v1/assets', [], b'', timeout, limit)
        self.assertEqual(self.connections, [])


if __name__ == '__main__':
    unittest.main()
