"""Concrete fixture entrypoint with fake runtime adapters and temporary source."""

import json
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest

from daily_local_fixture import execute, preflight


class Database:
    instances = []
    fail_migration = False
    fail_stop = False
    def __init__(self, *args):
        self.password = 'synthetic-only'
        self.stopped = False
        self.instances.append(self)
    def create(self): pass
    def wait_ready(self): pass
    def migrate(self, root):
        if self.fail_migration: raise RuntimeError('private-error')
    def stop(self):
        if self.fail_stop: raise RuntimeError('ownership mismatch')
        self.stopped = True


class Adapter:
    def __init__(self, *args): self.processes = SimpleNamespace(children={})


class Launcher:
    def __init__(self, adapter): self.owned = []
    def start(self): self.owned = ['fake-child']
    def stop(self): self.owned = []


class Client:
    def __init__(self, *args): pass
    def create_synthetic_asset(self): return 'fixture-asset'
    def assert_invalid_requests_rejected(self): pass
    def login_and_assert_asset(self, value): assert value == 'fixture-asset'


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.candidate = self.root / 'backend/.local/daily-candidates/synthetic'
        files = ('scripts/daily-local-backend.cjs', 'scripts/daily_local_gateway_child.py',
                 'backend/migrations/001-auth-accounts.sql', 'backend/migrations/002-assets.sql',
                 'cert.pem', 'key.pem',
                 'backend/.local/daily-candidates/synthetic/dist/main.js')
        for name in files:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('synthetic', encoding='utf-8')
        self.args = SimpleNamespace(execute_synthetic=True, image='sha256:' + 'b' * 64,
            candidate=str(self.candidate), cert=str(self.root / 'cert.pem'),
            key=str(self.root / 'key.pem'), db_port=29444, backend_port=29445, tls_port=29443)
        self.runtime = SimpleNamespace(env={}, remaining=lambda: 120,
                                       deadline=time.monotonic() + 120)
        Database.instances = []
        Database.fail_migration = Database.fail_stop = False

    def run_fixture(self):
        return execute(self.root, self.args, self.runtime, database_factory=Database,
            launcher_factory=Launcher, adapter_factory=Adapter, client_factory=Client,
            ports_free=lambda ports: None)

    def result(self):
        paths = list((self.root / '.local').glob('daily-runtime-*/result.json'))
        self.assertEqual(len(paths), 1)
        return json.loads(paths[0].read_text(encoding='utf-8'))

    def test_success_records_redacted_result_and_preserves_folder(self):
        result = self.run_fixture()
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(result['cleanup'], 'stopped')
        self.assertEqual(result['stage'], 'completed')
        self.assertNotIn('synthetic-only', json.dumps(self.result()))
        self.assertTrue(Database.instances[0].stopped)

    def test_opt_in_failure_before_any_fixture_write(self):
        self.args.execute_synthetic = False
        with self.assertRaises(ValueError): self.run_fixture()
        self.assertFalse((self.root / '.local').exists())
        self.assertEqual(Database.instances, [])

    def test_candidate_escape_and_reserved_port_refused(self):
        self.args.candidate = str(self.root)
        with self.assertRaises(ValueError): preflight(self.root, self.args)
        self.args.candidate = str(self.candidate)
        self.args.tls_port = 28443
        with self.assertRaises(ValueError): preflight(self.root, self.args)

    def test_migration_failure_stops_owned_database_and_records_failure(self):
        Database.fail_migration = True
        with self.assertRaises(RuntimeError): self.run_fixture()
        self.assertTrue(Database.instances[0].stopped)
        self.assertEqual(self.result()['status'], 'failed')
        self.assertEqual(self.result()['stage'], 'database-migrate')
        self.assertNotIn('private-error', json.dumps(self.result()))

    def test_ownership_failure_not_reported_clean(self):
        Database.fail_stop = True
        with self.assertRaises(RuntimeError): self.run_fixture()
        self.assertEqual(self.result()['cleanup'], 'incomplete')

    def test_missing_artifact_before_any_write(self):
        (self.candidate / 'dist/main.js').unlink()
        with self.assertRaises(ValueError): self.run_fixture()
        self.assertFalse((self.root / '.local').exists())
