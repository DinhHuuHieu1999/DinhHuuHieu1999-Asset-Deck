"""PostgreSQL lifecycle command contracts only; all Docker calls are fake."""

import json
import unittest
from pathlib import Path
import tempfile
from daily_local_profile import BASE, EXTENDED, profile_contract
from daily_local_fixture_database import LABEL, SyntheticDatabase


IDENTITY = 'a' * 32
IMAGE = 'sha256:' + 'b' * 64


class Runtime:
    env = {}
    def __init__(self):
        self.calls = []
        self.owner = IDENTITY
        self.database_identity = b'fixture|fixture'
    def remaining(self): return 120
    def run(self, command, **kwargs):
        self.calls.append((command, kwargs))
        if command[1:3] == ['image', 'inspect']: return IMAGE.encode()
        if command[1] == 'inspect': return json.dumps({LABEL: self.owner}).encode()
        if '-Atqc' in command: return self.database_identity
        return b''


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.runtime = Runtime()
        self.database = SyntheticDatabase(self.runtime, IMAGE, 29444, IDENTITY)

    def test_fresh_loopback_no_pull_no_password_argument(self):
        self.database.create()
        self.database.wait_ready()
        self.database.stop()
        commands = [command for command, _ in self.runtime.calls]
        create = next(command for command in commands if command[1] == 'create')
        self.assertIn('127.0.0.1:29444:5432', create)
        self.assertNotIn(self.database.password, str(commands))
        self.assertFalse(any('pull' in command or 'rm' in command for command in commands))

    def test_owner_mismatch_never_stops(self):
        self.database.creation_attempted = True
        self.runtime.owner = 'other'
        with self.assertRaises(RuntimeError): self.database.stop()
        self.assertFalse(any(command[1] == 'stop' for command, _ in self.runtime.calls))

    def test_wrong_database_fails_closed(self):
        self.runtime.database_identity = b'other|fixture'
        with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
            self.database.wait_ready()

    def test_missing_image_starts_nothing(self):
        self.runtime.run = lambda *args, **kwargs: b'wrong-image'
        with self.assertRaises(RuntimeError): self.database.create()
        self.assertFalse(self.database.creation_attempted)

    def test_invalid_inputs_before_commands(self):
        with self.assertRaises(ValueError): SyntheticDatabase(self.runtime, 'postgres:latest', 29444, IDENTITY)
        with self.assertRaises(ValueError): SyntheticDatabase(self.runtime, IMAGE, True, IDENTITY)
        self.assertEqual(self.runtime.calls, [])


class ProfileMigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = Runtime()
        self.folder = self.root / 'backend' / 'migrations'
        self.folder.mkdir(parents=True)
        for name in profile_contract(EXTENDED)['migrations']:
            (self.folder / name).write_bytes(('synthetic ' + name).encode())

    def test_explicit_profiles_apply_only_their_ordered_files(self):
        for profile in (BASE, EXTENDED):
            self.runtime.calls.clear()
            db = SyntheticDatabase(self.runtime, IMAGE, 29444, IDENTITY, profile=profile)
            db.migrate(self.root)
            actual = [kw['data'] for c, kw in self.runtime.calls if 'psql' in c]
            expected = [('synthetic ' + name).encode()
                        for name in profile_contract(profile)['migrations']]
            self.assertEqual(actual, expected)
            self.assertFalse(db.creation_attempted)

    def test_missing_last_file_executes_no_commands(self):
        (self.folder / profile_contract(EXTENDED)['migrations'][-1]).unlink()
        db = SyntheticDatabase(self.runtime, IMAGE, 29444, IDENTITY, profile=EXTENDED)
        with self.assertRaises(FileNotFoundError):
            db.migrate(self.root)
        self.assertEqual(self.runtime.calls, [])

    def test_empty_artifact_executes_no_commands(self):
        (self.folder / profile_contract(EXTENDED)['migrations'][-1]).write_bytes(b'')
        db = SyntheticDatabase(self.runtime, IMAGE, 29444, IDENTITY, profile=EXTENDED)
        with self.assertRaisesRegex(ValueError, 'migration artifact'):
            db.migrate(self.root)
        self.assertEqual(self.runtime.calls, [])

    def test_unknown_profile_fails_before_commands(self):
        with self.assertRaisesRegex(ValueError, 'Unknown daily runtime profile'):
            SyntheticDatabase(self.runtime, IMAGE, 29444, IDENTITY, profile='all')
        self.assertEqual(self.runtime.calls, [])

    def test_owner_change_between_migrations_prevents_next_sql(self):
        original = self.runtime.run
        def run(command, **kwargs):
            result = original(command, **kwargs)
            if 'psql' in command:
                self.runtime.owner = 'other'
            return result
        self.runtime.run = run
        db = SyntheticDatabase(self.runtime, IMAGE, 29444, IDENTITY, profile=EXTENDED)
        with self.assertRaisesRegex(RuntimeError, 'ownership mismatch'):
            db.migrate(self.root)
        self.assertEqual(sum('psql' in c for c, _ in self.runtime.calls), 1)
