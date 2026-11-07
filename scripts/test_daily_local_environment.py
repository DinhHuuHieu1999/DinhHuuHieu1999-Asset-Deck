"""No private files or environment values are read by these tests."""

import unittest
from daily_local_environment import backend_environment, FEATURES


class EnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.private = dict(AUTH_POSTGRES_URL='postgresql://synthetic:fake@127.0.0.1:29444/test',
                            JWT_ACCESS_SECRET='j' * 32, CSRF_SECRET='c' * 32)

    def test_security_and_disabled_defaults(self):
        env = backend_environment(self.private, {'NODE_OPTIONS': '--require attacker',
                                                  'PYTHONPATH': 'attacker'})
        self.assertNotIn('NODE_OPTIONS', env)
        self.assertNotIn('PYTHONPATH', env)
        self.assertTrue(all(env[name] == 'false' for name in FEATURES))
        self.assertEqual(env['CSRF_ENABLED'], 'true')

    def test_unknown_private_override_refused(self):
        self.private['CSRF_ENABLED'] = 'false'
        with self.assertRaisesRegex(ValueError, '^Unsupported private environment fields$'):
            backend_environment(self.private, {})

    def test_remote_or_invalid_database_refused(self):
        for url in ('postgres://user:secret@remote.invalid:5432/db',
                    'postgres://localhost/db', 'file:///secret', 'postgres://localhost:bad/db'):
            self.private['AUTH_POSTGRES_URL'] = url
            with self.assertRaisesRegex(ValueError, '^A separate loopback PostgreSQL URL is required$'):
                backend_environment(self.private, {})

    def test_short_secret_and_bad_flag_refused(self):
        self.private['CSRF_SECRET'] = 'short'
        with self.assertRaises(ValueError):
            backend_environment(self.private, {})
        self.private['CSRF_SECRET'] = 'c' * 32
        self.private[FEATURES[0]] = 'TRUE'
        with self.assertRaises(ValueError):
            backend_environment(self.private, {})
