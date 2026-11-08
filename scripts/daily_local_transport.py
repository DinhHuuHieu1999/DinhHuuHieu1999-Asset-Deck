"""Fixed-loopback HTTP transport; construction has no network side effects."""

import http.client
import socket
import threading
import time


def loopback_transport(port, connection_factory=http.client.HTTPConnection,
                       timer_factory=threading.Timer, clock=time.monotonic):
    """Build a bounded transport that never resolves a request-controlled host.

    A watchdog shuts down the socket at the total deadline, including while
    response headers are arriving. Redirect responses are returned, never followed.
    Socket behavior still requires a separately approved live fixture.
    """
    if type(port) is not int or not 1024 <= port <= 65535:
        raise ValueError('Invalid loopback port')

    def transport(method, target, headers, body, timeout, limit):
        if (type(timeout) not in (int, float) or not 0 < timeout <= 30
                or type(limit) is not int or not 0 < limit <= 16 * 1024 * 1024):
            raise ValueError('Invalid transport bounds')
        deadline = clock() + timeout
        connection = connection_factory('127.0.0.1', port, timeout=timeout)
        expired = threading.Event()

        def abort():
            expired.set()
            sock = connection.sock
            if sock is not None:
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            connection.close()

        timer = timer_factory(timeout, abort)
        timer.daemon = True
        try:
            timer.start()
            connection.connect()
            # A deadline close must not cause HTTPConnection to reconnect later.
            connection.auto_open = 0
            if expired.is_set() or clock() >= deadline:
                raise TimeoutError('Upstream deadline exceeded')
            connection.putrequest(method, target, skip_accept_encoding=True)
            for name, value in headers:
                connection.putheader(name, value)
            connection.putheader('Content-Length', str(len(body)))
            connection.putheader('Connection', 'close')
            connection.endheaders(body)
            response = connection.getresponse()
            chunks = []
            size = 0
            while True:
                if expired.is_set() or clock() >= deadline:
                    raise TimeoutError('Upstream deadline exceeded')
                chunk = response.read1(min(65536, limit - size + 1))
                if not chunk:
                    break
                chunks.append(chunk)
                size += len(chunk)
                if size > limit:
                    raise ValueError('Upstream size exceeded')
            if expired.is_set() or clock() >= deadline:
                raise TimeoutError('Upstream deadline exceeded')
            return response.status, response.getheaders(), b''.join(chunks)
        finally:
            timer.cancel()
            connection.close()

    return transport
