"""Synthetic command contracts only; no Docker, sockets or subprocesses."""
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('dates_recovery', Path(__file__).with_name('saved-filters-database-recovery.py'))
m = importlib.util.module_from_spec(spec)
spec2 = importlib.util.spec_from_file_location('dates_wrapper', Path(__file__).with_name('saved-filters-postgres-fixture.py'))
w = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(w)
spec.loader.exec_module(m)
client = w.repository.client
identity = 'a' * 32
name = 'asset-saved-filters-' + identity
database = 'asset_saved_filters_fixture_' + identity[:12]


class Runtime:
    deadline = time.monotonic() + 120
    def __init__(self):
        self.calls = []
        self.changed = False
        self.bad_dump = False
    def run(self, command, **kwargs):
        self.calls.append((command, kwargs))
        if 'pg_dump' in command:
            return b'bad' if self.bad_dump else b'PGDMPsynthetic'
        if 'psql' in command:
            if 'current_database()' in command[-1]: return (database + '|fixture').encode()
            rows = {'filters': [dict(id=str(i), owner_id=str(i)*24, name='Synthetic %_1',
                query_schema_version=1, query={'q':'%_1'}, version=2,
                created_at='fixed', updated_at='fixed') for i in (1,2)],
                'assets':[dict(id='asset',owner_id='1'*24,version=1)],
                'owners':['1'*24,'2'*24]}
            if self.changed and sum('psql' in c for c, _ in self.calls) > 1:
                rows['filters'][0]['query']['q'] = 'changed'
            return json.dumps(rows).encode()
        return b''


class RecoveryTests(unittest.TestCase):
    def test_invalid_identity_refuses_before_any_command(self):
        runtime = Runtime()
        with self.assertRaises(client.Refusal): m.verify(runtime, 'real-db', database, identity, Path('.'), client)
        self.assertEqual(runtime.calls, [])

    def test_complete_flow_retains_dump_and_restores_to_new_database(self):
        runtime = Runtime()
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned') as owned:
            m.verify(runtime, name, database, identity, Path(folder), client)
            result = json.loads((Path(folder) / 'saved-filters-recovery-result.json').read_text())
            self.assertEqual(result['definitions'], 2)
            self.assertTrue(result['databaseRestart'] and result['databaseRestore'])
            self.assertGreaterEqual(owned.call_count, 4)
            restore = next(c for c, _ in runtime.calls if 'pg_restore' in c)
            self.assertEqual(restore[-1], database + '_restored')
            self.assertEqual((Path(folder) / 'saved-filters-database.dump').read_bytes(), b'PGDMPsynthetic')
            self.assertFalse(any('rm' in c or 'dropdb' in c for c, _ in runtime.calls))

    def test_invalid_dump_never_stops_or_restores(self):
        runtime = Runtime(); runtime.bad_dump = True
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned'):
            with self.assertRaises(client.Refusal): m.verify(runtime, name, database, identity, Path(folder), client)
        self.assertFalse(any('stop' in c or 'pg_restore' in c for c, _ in runtime.calls))

    def test_changed_data_refuses_before_creating_restore_database(self):
        runtime = Runtime(); runtime.changed = True
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned'):
            with self.assertRaises(client.Refusal): m.verify(runtime, name, database, identity, Path(folder), client)
            self.assertFalse((Path(folder) / 'saved-filters-recovery-result.json').exists())
        self.assertFalse(any('createdb' in c for c, _ in runtime.calls))

    def test_existing_dump_is_not_overwritten(self):
        runtime = Runtime()
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned'):
            target = Path(folder) / 'saved-filters-database.dump'; target.write_bytes(b'keep')
            with self.assertRaises(client.Refusal): m.verify(runtime, name, database, identity, Path(folder), client)
            self.assertEqual(target.read_bytes(), b'keep')
        self.assertFalse(any('stop' in c for c, _ in runtime.calls))


class FailureTests(unittest.TestCase):
    def test_ownership_failure_prevents_dump_or_stop(self):
        runtime = Runtime()
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned', side_effect=client.Refusal('foreign')):
            with self.assertRaises(client.Refusal):
                m.verify(runtime, name, database, identity, Path(folder), client)
            self.assertEqual(list(Path(folder).iterdir()), [])
        self.assertEqual(runtime.calls, [])

    def test_existing_result_prevents_all_commands(self):
        runtime = Runtime()
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)/'saved-filters-recovery-result.json'
            target.write_text('keep', encoding='utf-8')
            with self.assertRaises(client.Refusal):
                m.verify(runtime, name, database, identity, Path(folder), client)
            self.assertEqual(target.read_text(), 'keep')
        self.assertEqual(runtime.calls, [])

    def test_readiness_deadline_prevents_restore(self):
        runtime = Runtime()
        runtime.deadline = time.monotonic() - 1
        original = runtime.run
        def run(command, **kwargs):
            if 'psql' in command and 'current_database()' in command[-1]:
                raise client.Refusal('not ready')
            return original(command, **kwargs)
        runtime.run = run
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned'):
            with self.assertRaises(client.Refusal):
                m.verify(runtime, name, database, identity, Path(folder), client)
        self.assertFalse(any('createdb' in c or 'pg_restore' in c for c, _ in runtime.calls))

    def test_empty_or_malformed_snapshot_refuses(self):
        for value in ({}, {'filters':[], 'assets':[], 'owners':[]}):
            runtime = Runtime()
            with patch.object(runtime, 'run', return_value=json.dumps(value).encode()):
                with self.assertRaises(ValueError): m.snapshot(runtime, name, database)

    def test_restore_difference_never_writes_success(self):
        runtime = Runtime()
        original = runtime.run
        def run(command, **kwargs):
            if 'pg_restore' in command: runtime.changed = True
            return original(command, **kwargs)
        runtime.run = run
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned'):
            with self.assertRaises(client.Refusal): m.verify(runtime, name, database, identity, Path(folder), client)
            self.assertFalse((Path(folder)/'saved-filters-recovery-result.json').exists())

    def test_wrong_database_on_restart_refuses(self):
        runtime = Runtime()
        original = runtime.run
        def run(command, **kwargs):
            if 'psql' in command and 'current_database()' in command[-1]: return b'wrong|fixture'
            return original(command, **kwargs)
        runtime.run = run
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned'):
            with self.assertRaises(client.Refusal): m.verify(runtime, name, database, identity, Path(folder), client)
        self.assertFalse(any('createdb' in c for c, _ in runtime.calls))


if __name__ == '__main__':
    unittest.main()
