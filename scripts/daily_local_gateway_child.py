"""Private-stdin gateway child. No server starts on import."""

import json
import sys
import threading

from daily_local_https import create_server


def serve(input_stream, notify, factory=create_server):
    """Read bounded private configuration, then stop accepting on control EOF."""
    line = input_stream.readline(16385)
    if len(line) > 16384 or not line.endswith(b'\n'):
        raise ValueError('Invalid gateway configuration')
    config = json.loads(line.decode('utf-8'))
    if type(config) is not dict or set(config) != {
            'backend_port', 'https_port', 'tls_cert', 'tls_key'}:
        raise ValueError('Invalid gateway configuration')
    server = factory(config)
    # A serving thread must be running before shutdown() can be called.
    worker = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.1},
                              daemon=True)
    worker.start()
    try:
        notify('ASSET_DESK_READY')
        # Only shutdown is supported; even invalid control input closes safely.
        input_stream.readline(65)
    finally:
        server.shutdown()
        server.server_close()
        server.drain()
        worker.join(timeout=2)
        if worker.is_alive():
            raise RuntimeError('Gateway shutdown incomplete')


if __name__ == '__main__':
    try:
        serve(sys.stdin.buffer, lambda event: print(event, flush=True))
    except Exception:
        print('Asset Desk gateway failed', file=sys.stderr)
        sys.exit(1)
