"""Foreground session adapter; no detached PID adoption or database lifecycle."""

import json
import socket
import threading
import time

from daily_local_process import OwnedProcesses, ProcessError


def assert_ports_free(ports):
    """Probe loopback binds without starting services; failure never kills a listener."""
    sockets = []
    try:
        for port in ports:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sockets.append(sock)
            if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            sock.bind(('127.0.0.1', port))
    finally:
        for sock in sockets:
            sock.close()


class DailyAdapter:
    """Use validated paths, exact commands and private child environments.

    The caller supplies a reviewed backend environment, never arbitrary argv.
    The database must already exist; this adapter cannot provision or remove it.
    """

    def __init__(self, config, environment, processes=None,
                 ports_free=assert_ports_free, clock=time.monotonic):
        self.config = config
        self.environment = dict(environment)
        self.processes = processes or OwnedProcesses()
        self.ports_free = ports_free
        self.clock = clock
        self.ready_events = {}

    def preflight(self, timeout):
        # Production env files would introduce unreviewed configuration fallbacks.
        for name in ('.env', '.env.production'):
            if (self.config['backend_cwd'] / 'env' / name).exists():
                raise ProcessError('Daily runtime refuses backend env-file fallbacks')
        self.ports_free((self.config['backend_port'], self.config['https_port']))

    def start(self, name, timeout):
        cfg = self.config
        if name == 'backend':
            argv = [str(cfg['node']), str(cfg['backend_supervisor'])]
            cwd = cfg['backend_cwd']
            env = dict(self.environment)
            env['NODE_ENV'] = 'production'
            env['BACKEND_HTTP_PORT'] = str(cfg['backend_port'])
        elif name == 'gateway':
            argv = [str(cfg['python']), '-E', '-s', '-B', str(cfg['gateway_entry'])]
            cwd = cfg['gateway_entry'].parent
            # Gateway does not need backend secrets or runtime feature flags.
            env = {key: value for key, value in self.environment.items()
                   if key.upper() in ('SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP')}
        elif name == 'app':
            argv, cwd = [str(cfg['app'])], cfg['app'].parent
            env = {key: value for key, value in self.environment.items()
                   if key.upper() in ('SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP', 'USERPROFILE',
                                      'LOCALAPPDATA', 'APPDATA')}
        else:
            raise ProcessError('Unknown component')
        identity = self.processes.start(name, argv, cwd, env)
        return identity

    def ready(self, name, identity, timeout):
        cfg = self.config
        deadline = self.clock() + timeout
        child = self.processes.children[name][1]
        if name != 'app':
            event = threading.Event()
            self.ready_events[name] = event
            def monitor():
                line = bytearray()
                while True:
                    char = child.stdout.read(1)
                    if not char:
                        return
                    if char == b'\n':
                        # Python text stdout uses CRLF on Windows; accept one CR only.
                        marker = line[:-1] if line.endswith(b'\r') else line
                        if marker == b'ASSET_DESK_READY':
                            event.set()
                        line.clear()
                    elif len(line) < 128:
                        line.extend(char)
                    else:
                        # Never accumulate unbounded diagnostic output.
                        line[:] = b'OVERLONG'
            threading.Thread(target=monitor, daemon=True).start()
        if name == 'gateway':
            wire = json.dumps({key: str(value) if key.startswith('tls_') else value
                               for key, value in cfg.items()
                               if key in ('backend_port', 'https_port', 'tls_cert', 'tls_key')})
            child.stdin.write((wire + '\n').encode('utf-8'))
            child.stdin.flush()
        if name != 'app':
            while not self.ready_events[name].is_set():
                if not self.processes.running(name, identity):
                    raise ProcessError('Child exited before readiness')
                remaining = deadline - self.clock()
                if remaining <= 0:
                    raise ProcessError('Child readiness deadline exceeded')
                self.ready_events[name].wait(min(0.05, remaining))
        if self.clock() >= deadline:
            raise ProcessError('Child readiness deadline exceeded')
        if not self.processes.running(name, identity):
            raise ProcessError('Child exited before readiness')

    def matches(self, name, identity):
        return self.processes.matches(name, identity)

    def running(self, name, identity):
        return self.processes.running(name, identity)

    def stop(self, name, identity, timeout):
        def shutdown(child, remaining):
            if name == 'app':
                # Preserve unsaved Flutter drafts: ask the operator to close it.
                raise ProcessError('Close the app before stopping the session')
            # Closing the private pipe is nonblocking and requests graceful EOF.
            child.stdin.close()
        self.processes.stop(name, identity, timeout, shutdown)
