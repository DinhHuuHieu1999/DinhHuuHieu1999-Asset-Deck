"""Adapter source integration using fake children; no processes or sockets."""

import io
from pathlib import Path
import unittest

from daily_local_adapter import DailyAdapter
from daily_local_lifecycle import Launcher
from daily_local_process import OwnedProcesses, ProcessError


class Child:
    def __init__(self):
        self.stdin = io.BytesIO()
        self.stdout = io.BytesIO(b'private-log\nASSET_DESK_READY\n')
        self.code = None

    def poll(self):
        return self.code

    def wait(self, timeout):
        if not self.stdin.closed:
            raise TimeoutError()
        self.code = 0


class AdapterTests(unittest.TestCase):
    def setUp(self):
        root = Path.cwd()
        self.cfg = {key: root / key for key in ('node', 'python', 'backend_supervisor',
                    'backend_cwd', 'gateway_entry', 'app', 'tls_cert', 'tls_key')}
        self.cfg.update(backend_port=29445, https_port=29443)
        self.calls = []
        def spawn(*args, **kwargs):
            self.calls.append((args, kwargs))
            return Child()
        self.adapter = DailyAdapter(self.cfg, {'SECRET': 'private', 'SYSTEMROOT': 'windows'},
                                    processes=OwnedProcesses(spawn), ports_free=lambda ports: None)

    def test_start_readiness_and_secret_isolation(self):
        launcher = Launcher(self.adapter)
        launcher.start()
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(self.calls[0][1]['env']['SECRET'], 'private')
        for _, kwargs in self.calls[1:]:
            self.assertNotIn('SECRET', kwargs['env'])
        for name in ('backend', 'gateway', 'app'):
            self.adapter.processes.children[name][1].code = 0
        launcher.stop()
        self.assertEqual(launcher.owned, [])

    def test_open_app_is_not_force_closed(self):
        launcher = Launcher(self.adapter)
        launcher.start()
        with self.assertRaises(Exception):
            launcher.stop()
        self.assertEqual([name for name, _ in launcher.owned], ['app'])

    def test_busy_port_starts_nothing(self):
        def busy(ports):
            raise OSError('occupied')
        self.adapter.ports_free = busy
        with self.assertRaises(Exception):
            Launcher(self.adapter).start()
        self.assertEqual(self.calls, [])

    def test_exited_child_fails_without_waiting_for_deadline(self):
        identity = self.adapter.start('backend', 30)
        child = self.adapter.processes.children['backend'][1]
        child.stdout = io.BytesIO(b'private failure without readiness\n')
        child.code = 1
        calls = []
        self.adapter.clock = lambda: calls.append(True) or 0
        with self.assertRaisesRegex(ProcessError, 'Child exited before readiness'):
            self.adapter.ready('backend', identity, 30)
        self.assertLessEqual(len(calls), 2)

    def test_windows_crlf_readiness_marker(self):
        identity = self.adapter.start('gateway', 1)
        child = self.adapter.processes.children['gateway'][1]
        child.stdout = io.BytesIO(b'ASSET_DESK_READY\r\n')
        self.adapter.ready('gateway', identity, 1)
        self.assertTrue(self.adapter.ready_events['gateway'].is_set())

    def test_malformed_marker_is_not_readiness(self):
        for wire in (b' ASSET_DESK_READY\r\n', b'ASSET_DESK_READY\r\r\n'):
            with self.subTest(wire=wire):
                adapter = DailyAdapter(self.cfg, {},
                    processes=OwnedProcesses(lambda *args, **kw: Child()),
                    ports_free=lambda ports: None)
                identity = adapter.start('backend', 1)
                adapter.processes.children['backend'][1].stdout = io.BytesIO(wire)
                with self.assertRaisesRegex(ProcessError, 'readiness deadline'):
                    adapter.ready('backend', identity, 0.03)
