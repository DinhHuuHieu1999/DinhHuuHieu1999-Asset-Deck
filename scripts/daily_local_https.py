"""Opt-in loopback HTTPS listener; importing this module starts nothing."""

from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
import socket
import ssl
import threading
import time

from daily_local_gateway import GatewayError, MAX_REQUEST, relay
from daily_local_transport import loopback_transport


def make_handler(transport):
    """Create a single-request handler with redacted logs and a total deadline."""
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.0'

        def __init__(self, request, address, server):
            def abort():
                try:
                    request.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                request.close()
            timer = threading.Timer(25, abort)
            timer.daemon = True
            timer.start()
            try:
                request.settimeout(20)
                # SSL handshake occurs in the bounded worker, not accept().
                request.do_handshake()
                super().__init__(request, address, server)
            finally:
                timer.cancel()

        def log_message(self, *args):
            pass

        def send_error(self, code, message=None, explain=None):
            # Never reflect malformed targets or request details in the response.
            self.send_response_only(code)
            self.send_header('Content-Length', '0')
            self.send_header('Connection', 'close')
            self.end_headers()
            self.close_connection = True

        def handle_expect_100(self):
            self.send_error(417)
            return False

        def _forward(self):
            try:
                hosts = self.headers.get_all('Host', [])
                port = getattr(self.server, 'server_port', None)
                allowed_hosts = ('localhost:{}'.format(port),
                                 '127.0.0.1:{}'.format(port))
                if len(hosts) != 1 or hosts[0].lower() not in allowed_hosts:
                    self.send_error(400)
                    return
                lengths = self.headers.get_all('Content-Length', [])
                if (len(lengths) > 1 or self.headers.get('Transfer-Encoding')
                        or self.headers.get('Expect')):
                    raise GatewayError('Invalid request framing')
                raw = lengths[0] if lengths else '0'
                if not raw.isascii() or not raw.isdigit() or len(raw) > 10:
                    raise GatewayError('Invalid request framing')
                size = int(raw)
                if size > MAX_REQUEST:
                    self.send_error(413)
                    return
                body = self.rfile.read(size)
                if len(body) != size:
                    raise GatewayError('Incomplete request')
                status, headers, payload = relay(
                    self.command, self.path, self.headers.items(), body, transport)
            except GatewayError:
                self.send_error(502)
                return
            except (OSError, ValueError):
                self.send_error(400)
                return
            self.send_response_only(status)
            for name, value in headers:
                self.send_header(name, value)
            self.send_header('Content-Length', str(len(payload)))
            self.send_header('Connection', 'close')
            self.end_headers()
            if self.command != 'HEAD':
                self.wfile.write(payload)
            self.close_connection = True

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = _forward

    return Handler


class BoundedServer(ThreadingMixIn, HTTPServer):
    """Limit concurrent workers; reject excess connections without spawning."""
    daemon_threads = True
    block_on_close = False
    allow_reuse_address = False

    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(8)
        self.active = 0
        self.drained = threading.Condition()
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        if not self.slots.acquire(False):
            self.shutdown_request(request)
            return
        with self.drained:
            self.active += 1
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            with self.drained:
                self.active -= 1
                self.drained.notify_all()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()
            with self.drained:
                self.active -= 1
                self.drained.notify_all()

    def drain(self, timeout=26):
        """Wait for bounded handlers after stopping acceptance; never wait forever."""
        deadline = time.monotonic() + timeout
        with self.drained:
            while self.active:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError('HTTPS requests did not drain before deadline')
                self.drained.wait(remaining)

    def handle_error(self, request, client_address):
        # No default traceback that could disclose paths or request data.
        pass


def create_server(config, context_factory=ssl.SSLContext,
                  server_factory=BoundedServer, transport_factory=loopback_transport):
    """Create but do not serve a listener from already validated configuration.

    Calling this function reads TLS material and binds a port: runtime approval
    is required. Tests inject all factories and do neither.
    """
    backend, https = config['backend_port'], config['https_port']
    if (type(backend) is not int or type(https) is not int
            or not 1024 <= backend <= 65535 or not 1024 <= https <= 65535
            or backend == https):
        raise ValueError('Invalid gateway ports')
    context = context_factory(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(str(config['tls_cert']), str(config['tls_key']))
    server = server_factory(('127.0.0.1', https),
                            make_handler(transport_factory(backend)), bind_and_activate=False)
    try:
        server.socket = context.wrap_socket(server.socket, server_side=True,
                                             do_handshake_on_connect=False)
        server.server_bind()
        server.server_activate()
        return server
    except Exception:
        server.server_close()
        raise RuntimeError('HTTPS listener initialization failed') from None
