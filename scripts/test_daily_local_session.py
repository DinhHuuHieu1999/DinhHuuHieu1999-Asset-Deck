"""Synthetic local lock files and injected command tests; no runtime children."""

import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock

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


class LauncherProfileTests(unittest.TestCase):
    def invoke(self, profile=None, execute=True, overrides=None):
        private = dict(AUTH_POSTGRES_URL='postgresql://fake:fake@127.0.0.1:29444/test',
                       JWT_ACCESS_SECRET='j' * 32, CSRF_SECRET='c' * 32)
        private.update(overrides or {})
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'synthetic.json'
            config.write_text('{}', encoding='utf-8')
            argv = ['--config', str(config)]
            if execute:
                argv.append('--execute-approved-local')
            if profile is not None:
                argv.extend(['--profile', profile])
            fake = MagicMock()
            fake.owned = []
            with patch.dict(launcher_module.os.environ, private, clear=True), \
                    patch.object(launcher_module, 'validate_config',
                                 return_value={'state_dir': Path(directory)}), \
                    patch.object(launcher_module, 'SessionLock') as lock, \
                    patch.object(launcher_module, 'DailyAdapter') as adapter, \
                    patch.object(launcher_module, 'Launcher', return_value=fake), \
                    patch.object(launcher_module, 'command_loop', return_value=True), \
                    patch('sys.stdout', new_callable=io.StringIO), \
                    patch('sys.stderr', new_callable=io.StringIO) as errors:
                result = launcher_module.main(argv)
                return result, lock, adapter, errors.getvalue()

    def test_extended_profile_applied_before_adapter(self):
        result, lock, adapter, _ = self.invoke('inventory-with-saved-filters')
        self.assertEqual(result, 0)
        environment = adapter.call_args[0][1]
        self.assertEqual(environment['ASSET_SAVED_FILTERS_ENABLED'], 'true')
        self.assertEqual(environment['ASSET_DATES_ENABLED'], 'true')
        self.assertTrue(all(value == 'false' for name, value in environment.items()
                            if name.startswith('ASSET_IMPORT')))
        lock.return_value.release.assert_called_once()

    def test_conflict_fails_before_lock_or_adapter(self):
        result, lock, adapter, errors = self.invoke(
            'inventory-with-saved-filters', overrides={'ASSET_IMPORT_ENABLED': 'true'})
        self.assertEqual(result, 1)
        lock.assert_not_called()
        adapter.assert_not_called()
        self.assertNotIn('fake:fake', errors)

    def test_omitted_profile_preserves_explicit_existing_environment(self):
        result, _, adapter, _ = self.invoke(overrides={'ASSET_DATES_ENABLED': 'true'})
        self.assertEqual(result, 0)
        self.assertEqual(adapter.call_args[0][1]['ASSET_DATES_ENABLED'], 'true')
        self.assertEqual(adapter.call_args[0][1]['ASSET_SAVED_FILTERS_ENABLED'], 'false')

    def test_dry_run_never_locks_or_builds_private_environment(self):
        result, lock, adapter, _ = self.invoke('inventory-with-saved-filters', execute=False,
                                              overrides={'ASSET_IMPORT_ENABLED': 'true'})
        self.assertEqual(result, 0)
        lock.assert_not_called()
        adapter.assert_not_called()

    def test_base_profile_rejects_optional_enablement(self):
        result, lock, adapter, _ = self.invoke('base', overrides={'ASSET_DATES_ENABLED': 'true'})
        self.assertEqual(result, 1)
        lock.assert_not_called()
        adapter.assert_not_called()
