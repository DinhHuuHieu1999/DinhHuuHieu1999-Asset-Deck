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


if __name__ == '__main__':
    unittest.main()
