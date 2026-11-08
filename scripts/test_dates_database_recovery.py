"""Synthetic command contracts only; no Docker, sockets or subprocesses."""
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('dates_recovery', Path(__file__).with_name('dates-database-recovery.py'))
m = importlib.util.module_from_spec(spec)
spec2 = importlib.util.spec_from_file_location('dates_wrapper', Path(__file__).with_name('dates-postgres-fixture.py'))
w = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(w)
spec.loader.exec_module(m)
client = w.repository.client
identity = 'a' * 32
name = 'asset-dates-' + identity
database = 'asset_dates_fixture_' + identity[:12]


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
            rows = [{'id': str(i), 'owner_id': 'b' * 24, 'version': 2,
                'purchased_on': '2000-02-29', 'warranty_expires_on': None} for i in range(4)]
            if self.changed and sum('psql' in c for c, _ in self.calls) > 1:
                rows[0]['purchased_on'] = None
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
            result = json.loads((Path(folder) / 'dates-recovery-result.json').read_text())
            self.assertEqual(result['records'], 4)
            self.assertTrue(result['restart'] and result['restore'])
            self.assertGreaterEqual(owned.call_count, 4)
            restore = next(c for c, _ in runtime.calls if 'pg_restore' in c)
            self.assertEqual(restore[-1], database + '_restored')
            self.assertEqual((Path(folder) / 'dates-database.dump').read_bytes(), b'PGDMPsynthetic')
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
            self.assertFalse((Path(folder) / 'dates-recovery-result.json').exists())
        self.assertFalse(any('createdb' in c for c, _ in runtime.calls))

    def test_existing_dump_is_not_overwritten(self):
        runtime = Runtime()
        with tempfile.TemporaryDirectory() as folder, patch.object(client, 'assert_owned'):
            target = Path(folder) / 'dates-database.dump'; target.write_bytes(b'keep')
            with self.assertRaises(FileExistsError): m.verify(runtime, name, database, identity, Path(folder), client)
            self.assertEqual(target.read_bytes(), b'keep')
        self.assertFalse(any('stop' in c for c, _ in runtime.calls))


if __name__ == '__main__':
    unittest.main()
