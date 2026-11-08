"""Offline contracts: no Docker, process, socket or TLS reads are permitted."""
import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location('fixture', Path(__file__).with_name('client-https-fixture.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def arguments():
    return argparse.Namespace(execute_synthetic=True, image='sha256:' + 'a' * 64,
                              cert='', key='', dart='dart', db_port=19001, backend_port=19002, tls_port=19003)


class FakeRuntime:
    def __init__(self, fail_driver=False, wrong_owner=False):
        self.env = {'PATH': 'synthetic'}
        self.deadline = time.monotonic() + 300
        self.calls = []
        self.identity = None
        self.fail_driver = fail_driver
        self.wrong_owner = wrong_owner
        self.stopped = False

    def run(self, command, **kwargs):
        self.calls.append(command)
        if command[:3] == ['docker', 'image', 'inspect']:
            return ('sha256:' + 'a' * 64).encode()
        if command[:3] == ['docker', 'volume', 'create']:
            self.identity = command[4].split('=')[1]
        if command[:2] == ['docker', 'inspect']:
            return json.dumps({fixture.LABEL: 'wrong' if self.wrong_owner else self.identity}).encode()
        if '-Atqc' in command:
            return b'fixture|fixture\n'
        if command[0] == 'dart':
            if self.fail_driver:
                raise fixture.Refusal('Synthetic failure')
            return json.dumps({'status': 'completed', 'syntheticOnly': True, 'assetCount': 51, 'owners': 2}).encode()
        return b''

    def start(self, command, cwd, env=None):
        self.calls.append(command)
        if command[0] == 'node' and command[-1].endswith('main.js'):
            assert not (cwd / 'env').exists()
            assert env['CSRF_COOKIE_SECURE'] == 'true'
            assert env['AUTH_EXPOSE_RESET_TOKEN'] == 'false'
        return object()

    def wait_port(self, port, child):
        pass

    def wait_backend(self, folder, identity, port, child):
        pass

    def stop_children(self):
        self.stopped = True


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in fixture.FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        self.args = arguments()
        for key in ('cert', 'key'):
            path = self.root / key
            path.write_text('not TLS material', encoding='utf-8')
            setattr(self.args, key, str(path))
        # Tests fail immediately on accidental real side effects.
        for name in ('subprocess.run', 'subprocess.Popen', 'socket.create_connection'):
            guard = patch.object(fixture.subprocess if name.startswith('subprocess') else fixture.socket,
                                 name.split('.')[1], side_effect=AssertionError('Forbidden IO'))
            guard.start()
            self.addCleanup(guard.stop)
        self.socket = patch.object(fixture.socket, 'socket')
        self.mock_socket = self.socket.start()
        self.addCleanup(self.socket.stop)
        self.mock_socket.return_value.__enter__.return_value.connect_ex.return_value = 1
        self.which = patch.object(fixture.shutil, 'which', return_value='synthetic-dart.exe')
        self.which.start()
        self.addCleanup(self.which.stop)

    def test_preflight_does_not_read_tls_or_write(self):
        with patch.object(Path, 'read_bytes', side_effect=AssertionError('No reads')):
            fixture.preflight(self.root, self.args)
        self.assertFalse((self.root / '.local').exists())

    def test_progress_contains_only_fixed_milestones_and_is_flushed(self):
        identity = 'a' * 32
        with patch.object(fixture.os, 'fsync') as sync:
            fixture.record_progress(self.root, identity, 'database-create')
            fixture.record_progress(self.root, identity, 'database-readiness')
        rows = [json.loads(line) for line in (self.root/'progress.jsonl').read_text().splitlines()]
        self.assertEqual(rows, [{'fixtureId': identity, 'stage': name}
                                for name in ('database-create', 'database-readiness')])
        self.assertEqual(sync.call_count, 2)
        with self.assertRaises(FileExistsError):
            fixture.record_progress(self.root, identity, 'database-create')
        before = (self.root/'progress.jsonl').read_bytes()
        with self.assertRaises(fixture.Refusal):
            fixture.record_progress(self.root, identity, 'private-command-or-password')
        self.assertEqual((self.root/'progress.jsonl').read_bytes(), before)

    def test_progress_failure_before_creation_refuses_without_creating_volume(self):
        runtime = FakeRuntime()
        with patch.object(fixture, 'record_progress', side_effect=OSError('synthetic disk error')):
            with self.assertRaises(OSError):
                fixture.execute(self.root, self.args, runtime)
        self.assertFalse(any(c[:3] == ['docker', 'volume', 'create'] for c in runtime.calls))
        self.assertTrue(runtime.stopped)

    def test_progress_failure_after_readiness_still_cleans_up_owned_resources(self):
        runtime = FakeRuntime()
        original = fixture.record_progress
        def fail_at_migrations(folder, identity, stage):
            if stage == 'migrations':
                raise OSError('synthetic private error')
            original(folder, identity, stage)
        with patch.object(fixture, 'record_progress', side_effect=fail_at_migrations):
            with self.assertRaises(OSError):
                fixture.execute(self.root, self.args, runtime)
        folder = self.root / '.local' / ('asset-client-' + runtime.identity)
        rows = [json.loads(line) for line in (folder/'progress.jsonl').read_text().splitlines()]
        self.assertEqual([row['stage'] for row in rows], ['database-create', 'database-readiness'])
        self.assertTrue(runtime.stopped)
        self.assertTrue(any(c[:2] == ['docker', 'stop'] for c in runtime.calls))
        self.assertEqual(json.loads((folder/'result.json').read_text())['cleanup'], 'stopped')

    def test_no_opt_in_refuses_before_any_io(self):
        self.args.execute_synthetic = False
        with patch.object(Path, 'is_file', side_effect=AssertionError('No IO')):
            with self.assertRaises(fixture.Refusal):
                fixture.preflight(self.root, self.args)
        self.mock_socket.assert_not_called()

    def test_each_missing_artifact_refuses_without_side_effects(self):
        original = Path.is_file
        for missing in fixture.FILES:
            with self.subTest(missing=missing):
                with patch.object(Path, 'is_file', lambda path: False if path == self.root / missing else original(path)):
                    with self.assertRaises(fixture.Refusal):
                        fixture.preflight(self.root, self.args)
        self.mock_socket.assert_not_called()

    def test_invalid_ports_image_tls_and_tools_refuse(self):
        for field, value in [('image', 'postgres:latest'), ('db_port', 8443), ('tls_port', 19002), ('cert', 'relative.crt')]:
            args = arguments()
            args.cert, args.key = self.args.cert, self.args.key
            setattr(args, field, value)
            with self.subTest(field=field), self.assertRaises(fixture.Refusal):
                fixture.preflight(self.root, args)
        with patch.object(fixture.shutil, 'which', return_value=None):
            with self.assertRaises(fixture.Refusal):
                fixture.preflight(self.root, self.args)

    def test_backend_readiness_requires_exact_child_pid_identity_and_port(self):
        runtime = fixture.Runtime()
        child = MagicMock(pid=42)
        child.poll.return_value = None
        marker = self.root / 'backend-ready.json'
        expected = {'fixtureId': 'a' * 32, 'pid': 42, 'port': 19002}
        for wrong in ({}, dict(expected, pid=43), dict(expected, port=19003), dict(expected, fixtureId='b' * 32)):
            marker.write_text(json.dumps(wrong), encoding='utf-8')
            with self.subTest(wrong=wrong), self.assertRaises(fixture.Refusal):
                runtime.wait_backend(self.root, 'a' * 32, 19002, child)
        marker.write_text(json.dumps(expected), encoding='utf-8')
        runtime.wait_backend(self.root, 'a' * 32, 19002, child)
        child.poll.return_value = 1
        with self.assertRaises(fixture.Refusal):
            runtime.wait_backend(self.root, 'a' * 32, 19002, child)

    def test_wrong_database_identity_never_reaches_migrations_or_backend(self):
        runtime = FakeRuntime()
        runtime.deadline = 300
        original = runtime.run
        def run(command, **kwargs):
            if '-Atqc' in command:
                runtime.calls.append(command)
                return b'wrong|fixture\n'
            return original(command, **kwargs)
        runtime.run = run
        with patch.object(fixture.time, 'monotonic', side_effect=[0, 0, 31, 31]), patch.object(fixture.time, 'sleep'):
            with self.assertRaises(fixture.Refusal):
                fixture.execute(self.root, self.args, runtime)
        self.assertFalse(any('-i' in c and 'psql' in c for c in runtime.calls))
        self.assertFalse(any(c[0] in ('node', 'dart') for c in runtime.calls))
        report = json.loads(next((self.root / '.local').glob('*/result.json')).read_text())
        self.assertEqual(report['stage'], 'database-readiness')
        self.assertEqual(report['cleanup'], 'stopped')

    def test_malformed_ownership_is_refused(self):
        for value in (None, [], {}, {'unrelated': 'value'}):
            runtime = MagicMock()
            runtime.run.return_value = json.dumps(value).encode()
            with self.subTest(value=value), self.assertRaises(fixture.Refusal):
                fixture.assert_owned(runtime, 'synthetic', 'a' * 32)

    def test_success_keeps_volume_and_stops_owned_resources(self):
        runtime = FakeRuntime()
        result = fixture.execute(self.root, self.args, runtime)
        self.assertEqual(result['assetCount'], 51)
        readiness = next(c for c in runtime.calls if '-Atqc' in c)
        self.assertIn('127.0.0.1', readiness)
        self.assertIn('PGPASSWORD', readiness)
        self.assertFalse(any('pg_isready' in c for c in runtime.calls))
        self.assertTrue(runtime.stopped)
        self.assertEqual(sum(c[:2] == ['docker', 'stop'] for c in runtime.calls), 1)
        self.assertFalse(any('rm' in c or 'pull' in c or 'build' in c for c in runtime.calls))
        self.assertEqual(sum('psql' in c and '-i' in c for c in runtime.calls), 2)
        self.assertEqual(sum(c[0] == 'dart' for c in runtime.calls), 1)
        self.assertIn('--disable-dart-dev', next(c for c in runtime.calls if c[0] == 'dart'))
        self.assertEqual(len(list((self.root / '.local').glob('*/result.json'))), 1)

    def test_driver_failure_cleans_up_without_retry(self):
        runtime = FakeRuntime(fail_driver=True)
        with self.assertRaises(fixture.Refusal):
            fixture.execute(self.root, self.args, runtime)
        self.assertTrue(runtime.stopped)
        self.assertEqual(sum(c[0] == 'dart' for c in runtime.calls), 1)
        self.assertEqual(sum(c[:2] == ['docker', 'stop'] for c in runtime.calls), 1)
        report = json.loads(next((self.root / '.local').glob('*/result.json')).read_text())
        self.assertEqual(report['status'], 'failed')

    def test_child_cleanup_failure_still_stops_owned_container_and_records_failure(self):
        runtime = FakeRuntime()
        runtime.stop_children = MagicMock(side_effect=fixture.Refusal('Synthetic stop failure'))
        with self.assertRaises(fixture.Refusal):
            fixture.execute(self.root, self.args, runtime)
        self.assertEqual(sum(c[:2] == ['docker', 'stop'] for c in runtime.calls), 1)
        report = json.loads(next((self.root / '.local').glob('*/result.json')).read_text())
        self.assertEqual(report['cleanup'], 'incomplete')
        self.assertEqual(report['status'], 'failed')

    def test_wrong_ownership_never_stops_container(self):
        runtime = FakeRuntime(wrong_owner=True)
        with self.assertRaises(fixture.Refusal):
            fixture.execute(self.root, self.args, runtime)
        self.assertTrue(runtime.stopped)
        self.assertFalse(any(c[:2] == ['docker', 'stop'] for c in runtime.calls))
        self.assertFalse(any(c[:2] == ['docker', 'start'] for c in runtime.calls))

    def test_native_callback_reuses_owned_cleanup_without_cli_driver(self):
        runtime = FakeRuntime()
        callback = MagicMock(return_value={'status': 'session-ended', 'nativeAcceptance': 'pending'})
        result = fixture.execute(self.root, self.args, runtime, callback)
        callback.assert_called_once()
        self.assertEqual(result['status'], 'session-ended')
        self.assertEqual(result['cleanup'], 'stopped')
        self.assertTrue(runtime.stopped)
        self.assertFalse(any(c[0] == 'dart' for c in runtime.calls))

    def test_native_callback_failure_still_stops_resources_without_retry(self):
        runtime = FakeRuntime()
        callback = MagicMock(side_effect=fixture.Refusal('Synthetic native failure'))
        with self.assertRaises(fixture.Refusal):
            fixture.execute(self.root, self.args, runtime, callback)
        callback.assert_called_once()
        self.assertTrue(runtime.stopped)
        self.assertEqual(sum(c[:2] == ['docker', 'stop'] for c in runtime.calls), 1)

    def test_import_profile_refuses_ambiguous_values_before_runtime(self):
        for value in ('true', 1, None):
            self.args.import_mode = value
            runtime = FakeRuntime()
            with self.assertRaises(fixture.Refusal):
                fixture.execute(self.root, self.args, runtime)
            self.assertEqual(runtime.calls, [])

    def test_import_requires_driver_and_all_fixed_artifacts_before_runtime(self):
        self.args.import_mode = True
        runtime = FakeRuntime()
        with self.assertRaises(fixture.Refusal):
            fixture.execute(self.root, self.args, runtime)
        self.assertEqual(runtime.calls, [])
        for name in fixture.IMPORT_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        for name in fixture.IMPORT_FILES:
            path = self.root / name
            path.unlink()
            with self.assertRaises(fixture.Refusal):
                fixture.execute(self.root, self.args, runtime, MagicMock())
            self.assertEqual(runtime.calls, [])
            path.write_text('synthetic', encoding='utf-8')

    def test_import_profile_uses_three_migrations_and_explicit_child_flags(self):
        self.args.import_mode = True
        for name in fixture.IMPORT_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        runtime = FakeRuntime()
        original = runtime.start
        environments = []
        def start(command, cwd, env=None):
            environments.append(env)
            return original(command, cwd, env)
        runtime.start = start
        callback = MagicMock(return_value={'status': 'completed'})
        report = fixture.execute(self.root, self.args, runtime, callback)
        self.assertEqual(environments[0]['ASSET_IMPORT_ENABLED'], 'true')
        proxy = next(c for c in runtime.calls if 'scripts' in ' '.join(c) and '--synthetic-only' in c)
        self.assertEqual(proxy[-1], '--import-enabled')
        self.assertEqual(sum('psql' in c and '-i' in c for c in runtime.calls), 3)
        self.assertTrue(set(fixture.IMPORT_FILES).issubset(report['sourceHashes']))
        self.assertEqual(report['cleanup'], 'stopped')
        callback.assert_called_once()

    def test_default_profile_explicitly_disables_inherited_location(self):
        runtime = FakeRuntime()
        runtime.env['ASSET_LOCATION_ENABLED'] = 'true'
        original = runtime.start
        environments = []
        def start(command, cwd, env=None):
            environments.append(env)
            return original(command, cwd, env)
        runtime.start = start
        fixture.execute(self.root, self.args, runtime)
        self.assertEqual(environments[0]['ASSET_LOCATION_ENABLED'], 'false')

    def test_location_profile_has_fixed_migrations_flags_and_proxy(self):
        self.args.location_mode = True
        for name in fixture.LOCATION_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        runtime = FakeRuntime()
        runtime.env['ASSET_LOCATION_ENABLED'] = 'inherited-must-not-win'
        original = runtime.start
        environments = []
        def start(command, cwd, env=None):
            environments.append(env)
            return original(command, cwd, env)
        runtime.start = start
        callback = MagicMock(return_value={'status': 'completed'})
        report = fixture.execute(self.root, self.args, runtime, callback)
        self.assertEqual(environments[0]['ASSET_LOCATION_ENABLED'], 'true')
        self.assertEqual(environments[0]['ASSET_IMPORT_V2_ENABLED'], 'false')
        self.assertEqual(environments[0]['ASSET_DATES_ENABLED'], 'true')
        self.assertEqual(environments[0]['ASSET_IMPORT_ENABLED'], 'false')
        proxy = next(c for c in runtime.calls if 'scripts' in ' '.join(c) and '--synthetic-only' in c)
        self.assertEqual(proxy[-1], '--location-enabled')
        self.assertEqual(sum('psql' in c and '-i' in c for c in runtime.calls), 4)
        self.assertTrue(set(fixture.LOCATION_FILES).issubset(report['sourceHashes']))
        self.assertEqual(report['cleanup'], 'stopped')
        callback.assert_called_once()


    def test_check_profile_has_fixed_migrations_flags_and_proxy(self):
        self.args.check_mode = True
        for name in fixture.CHECK_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        runtime = FakeRuntime()
        runtime.env['ASSET_LOCATION_ENABLED'] = 'inherited-must-not-win'
        original = runtime.start
        environments = []
        def start(command, cwd, env=None):
            environments.append(env)
            return original(command, cwd, env)
        runtime.start = start
        callback = MagicMock(return_value={'status': 'completed'})
        report = fixture.execute(self.root, self.args, runtime, callback)
        self.assertEqual(environments[0]['ASSET_CHECK_ENABLED'], 'true')
        self.assertEqual(environments[0]['ASSET_LOCATION_ENABLED'], 'true')
        self.assertEqual(environments[0]['ASSET_IMPORT_V2_ENABLED'], 'false')
        self.assertEqual(environments[0]['ASSET_DATES_ENABLED'], 'true')
        self.assertEqual(environments[0]['ASSET_IMPORT_ENABLED'], 'false')
        proxy = next(c for c in runtime.calls if 'scripts' in ' '.join(c) and '--synthetic-only' in c)
        self.assertEqual(proxy[-1], '--check-enabled')
        self.assertEqual(sum('psql' in c and '-i' in c for c in runtime.calls), 5)
        self.assertTrue(set(fixture.CHECK_FILES).issubset(report['sourceHashes']))
        self.assertEqual(report['cleanup'], 'stopped')
        callback.assert_called_once()


    def test_dates_profile_uses_three_migrations_and_explicit_child_flags(self):
        self.args.dates_mode = True
        for name in fixture.DATES_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        runtime = FakeRuntime()
        original = runtime.start
        environments = []
        def start(command, cwd, env=None):
            environments.append(env)
            return original(command, cwd, env)
        runtime.start = start
        callback = MagicMock(return_value={'status': 'completed'})
        report = fixture.execute(self.root, self.args, runtime, callback)
        self.assertEqual(environments[0]['ASSET_DATES_ENABLED'], 'true')
        self.assertEqual(environments[0]['ASSET_IMPORT_ENABLED'], 'false')
        proxy = next(c for c in runtime.calls if 'scripts' in ' '.join(c) and '--synthetic-only' in c)
        self.assertEqual(proxy[-1], '--dates-enabled')
        self.assertEqual(sum('psql' in c and '-i' in c for c in runtime.calls), 3)
        self.assertTrue(set(fixture.DATES_FILES).issubset(report['sourceHashes']))
        self.assertEqual(report['cleanup'], 'stopped')
        callback.assert_called_once()


    def test_v2_profile_requires_boolean_and_exclusive_selection(self):
        for values in [dict(import_v2_mode='true'), dict(import_v2_mode=True, import_mode=True),
                       dict(import_v2_mode=True, dates_mode=True)]:
            with self.assertRaises(fixture.Refusal):
                fixture.fixture_files(argparse.Namespace(**values))
        self.assertEqual(fixture.fixture_files(arguments()), fixture.FILES)

    def test_v2_missing_each_artifact_refuses_before_process(self):
        self.args.import_v2_mode = True
        for name in fixture.IMPORT_V2_FILES:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('synthetic', encoding='utf-8')
        runtime = FakeRuntime()
        for name in fixture.IMPORT_V2_FILES:
            p = self.root / name
            p.unlink()
            with self.assertRaises(fixture.Refusal):
                fixture.execute(self.root, self.args, runtime, MagicMock())
            self.assertEqual(runtime.calls, [])
            p.write_text('synthetic', encoding='utf-8')

    def check_v2_flags(self, disabled=False):
        self.args.import_v2_mode = True
        for name in fixture.IMPORT_V2_FILES:
            p = self.root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('synthetic', encoding='utf-8')
        self.args.disabled_v2_route = disabled
        runtime = FakeRuntime()
        original = runtime.start
        environments = []
        def start(command, cwd, env=None):
            environments.append(env)
            return original(command, cwd, env)
        runtime.start = start
        report = fixture.execute(self.root, self.args, runtime, MagicMock(return_value={}))
        for flag in ('ASSET_IMPORT_ENABLED', 'ASSET_DATES_ENABLED', 'ASSET_IMPORT_V2_ENABLED'):
            self.assertEqual(environments[0][flag], 'false' if disabled and flag == 'ASSET_IMPORT_V2_ENABLED' else 'true')
        proxy = next(c for c in runtime.calls if '--synthetic-only' in c)
        self.assertEqual(proxy[-1], '--import-v2-enabled')
        self.assertEqual(sum('psql' in c and '-i' in c for c in runtime.calls), 4)
        self.assertEqual(report['cleanup'], 'stopped')

    def test_v2_four_migrations_and_explicit_flags(self): self.check_v2_flags()
    def test_disabled_v2_keeps_proxy_route_but_disables_backend_module(self): self.check_v2_flags(True)

    def test_v3_profile_exclusive_and_default_off(self):
        self.assertFalse(fixture.import_v3_mode(arguments()))
        for value in ('true', 1, None):
            with self.assertRaises(fixture.Refusal):
                fixture.fixture_files(argparse.Namespace(import_v3_mode=value))
        for flag in ('import_mode', 'dates_mode', 'import_v2_mode', 'location_mode', 'export_v3_mode'):
            with self.assertRaises(fixture.Refusal):
                fixture.fixture_files(argparse.Namespace(import_v3_mode=True, **{flag: True}))
        self.assertNotIn('backend/dist/domains/assets/asset-import-v3.module.js', fixture.fixture_files(arguments()))

    def test_v3_missing_each_artifact_refuses_before_any_command(self):
        self.args.import_v3_mode = True
        for name in fixture.IMPORT_V3_FILES:
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        for name in fixture.IMPORT_V3_FILES:
            path = self.root/name
            path.unlink()
            runtime = FakeRuntime()
            with self.assertRaises(fixture.Refusal):
                fixture.execute(self.root, self.args, runtime, MagicMock())
            self.assertEqual(runtime.calls, [])
            path.write_text('synthetic', encoding='utf-8')

    def check_v3_flags(self, disabled=False):
        for name in fixture.FILES[1:3]:
            (self.root/name).write_text(name, encoding='utf-8')
        self.args.import_v3_mode = True
        self.args.disabled_v3_route = disabled
        for name in fixture.IMPORT_V3_FILES:
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name, encoding='utf-8')
        runtime = FakeRuntime()
        runtime.env['ASSET_IMPORT_V3_ENABLED'] = 'inherited-must-not-win'
        original_run, original_start = runtime.run, runtime.start
        migrations, environments = [], []
        def run(command, **kwargs):
            if 'psql' in command and '-i' in command:
                migrations.append(kwargs['data'])
            return original_run(command, **kwargs)
        def start(command, cwd, env=None):
            environments.append(env)
            return original_start(command, cwd, env)
        runtime.run, runtime.start = run, start
        report = fixture.execute(self.root, self.args, runtime, MagicMock(return_value={}))
        for flag in ('ASSET_IMPORT_ENABLED', 'ASSET_DATES_ENABLED', 'ASSET_LOCATION_ENABLED', 'ASSET_EXPORT_V3_ENABLED'):
            self.assertEqual(environments[0][flag], 'true')
        self.assertEqual(environments[0]['ASSET_IMPORT_V2_ENABLED'], 'false')
        self.assertEqual(environments[0]['ASSET_IMPORT_V3_ENABLED'], 'false' if disabled else 'true')
        proxy = next(command for command in runtime.calls if '--synthetic-only' in command)
        self.assertEqual(proxy[-1], '--import-v3-enabled')
        self.assertEqual(migrations, [name.encode() for name in (
            'backend/migrations/001-auth-accounts.sql', 'backend/migrations/002-assets.sql',
            'backend/migrations/003-asset-import.sql', 'backend/migrations/004-asset-dates.sql',
            'backend/migrations/005-asset-location.sql')])
        self.assertEqual(report['cleanup'], 'stopped')
        self.assertEqual(sum(command[:2] == ['docker', 'stop'] for command in runtime.calls), 1)

    def test_v3_five_migrations_and_fixed_child_flags(self): self.check_v3_flags()
    def test_disabled_v3_keeps_proxy_but_not_backend_module(self): self.check_v3_flags(True)

    def check_v4_flags(self, disabled=False):
        for name in fixture.FILES[1:3]:
            (self.root/name).write_text(name, encoding='utf-8')
        self.args.import_v4_mode = True
        self.args.disabled_v4_route = disabled
        for name in fixture.fixture_files(self.args):
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(name, encoding='utf-8')
        runtime = FakeRuntime()
        runtime.env['ASSET_IMPORT_V4_ENABLED'] = 'inherited-must-not-win'
        original_run, original_start = runtime.run, runtime.start
        migrations, environments = [], []
        def run(command, **kwargs):
            if 'psql' in command and '-i' in command:
                migrations.append(kwargs['data'])
            return original_run(command, **kwargs)
        def start(command, cwd, env=None):
            environments.append(env)
            return original_start(command, cwd, env)
        runtime.run, runtime.start = run, start
        report = fixture.execute(self.root, self.args, runtime, MagicMock(return_value={}))
        for flag in ('ASSET_IMPORT_ENABLED', 'ASSET_DATES_ENABLED', 'ASSET_LOCATION_ENABLED', 'ASSET_EXPORT_V3_ENABLED', 'ASSET_EXPORT_V4_ENABLED', 'ASSET_CHECK_ENABLED'):
            self.assertEqual(environments[0][flag], 'true')
        self.assertEqual(environments[0]['ASSET_IMPORT_V2_ENABLED'], 'false')
        self.assertEqual(environments[0]['ASSET_IMPORT_V3_ENABLED'], 'false')
        self.assertEqual(environments[0]['ASSET_IMPORT_V4_ENABLED'], 'false' if disabled else 'true')
        proxy = next(command for command in runtime.calls if '--synthetic-only' in command)
        self.assertEqual(proxy[-1], '--import-v4-enabled')
        self.assertEqual(migrations, [name.encode() for name in (
            'backend/migrations/001-auth-accounts.sql', 'backend/migrations/002-assets.sql',
            'backend/migrations/003-asset-import.sql', 'backend/migrations/004-asset-dates.sql',
            'backend/migrations/005-asset-location.sql', 'backend/migrations/006-asset-check.sql')])
        self.assertEqual(report['cleanup'], 'stopped')
        self.assertEqual(sum(command[:2] == ['docker', 'stop'] for command in runtime.calls), 1)

    def test_v4_six_migrations_and_fixed_child_flags(self): self.check_v4_flags()
    def test_disabled_v4_keeps_proxy_but_not_backend_module(self): self.check_v4_flags(True)


if __name__ == '__main__':
    unittest.main()
