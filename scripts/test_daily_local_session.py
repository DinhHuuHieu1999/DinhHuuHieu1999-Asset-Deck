"""Synthetic local lock files and injected command tests; no runtime children."""

import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

from daily_local_session import SessionLock

spec = importlib.util.spec_from_file_location('daily_launcher',
                                            Path(__file__).with_name('daily-local-launcher.py'))
launcher_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher_module)


class SessionTests(unittest.TestCase):
    def test_lock_excludes_second_and_releases_owned(self):
        with tempfile.TemporaryDirectory() as directory:
            lock = SessionLock(Path(directory))
            lock.acquire()
            with self.assertRaises(FileExistsError):
                SessionLock(Path(directory)).acquire()
            lock.release()
            self.assertFalse(lock.path.exists())

    def test_changed_token_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            lock = SessionLock(Path(directory))
            lock.acquire()
            lock.path.write_text('other-session', encoding='utf-8')
            with self.assertRaises(RuntimeError):
                lock.release()
            self.assertEqual(lock.path.read_text(encoding='utf-8'), 'other-session')

    def test_commands_and_eof_cleanup(self):
        events = []
        class FakeLauncher:
            def start(self): events.append('start')
            def status(self): return {'backend': True}
            def stop(self): events.append('stop')
        output = []
        result = launcher_module.command_loop(FakeLauncher(),
                    io.StringIO('start\nstatus\nsecret-command\nquit\n'), output.append)
        self.assertTrue(result)
        self.assertEqual(events, ['start', 'stop'])
        self.assertNotIn('secret-command', '\n'.join(output))

    def test_eof_failure_does_not_report_clean(self):
        class FakeLauncher:
            def stop(self): raise RuntimeError('private-secret')
        output = []
        self.assertFalse(launcher_module.command_loop(FakeLauncher(), io.StringIO(''), output.append))
        self.assertNotIn('private-secret', '\n'.join(output))
