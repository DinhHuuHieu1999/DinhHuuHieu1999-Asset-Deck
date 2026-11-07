"""PostgreSQL lifecycle command contracts only; all Docker calls are fake."""

import json
import unittest
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
