"""Offline profile contracts; no subprocess, network, private files or database."""

import unittest

from daily_local_environment import FEATURES
from daily_local_profile import BASE, EXTENDED, profile_contract, profile_environment


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.private = dict(AUTH_POSTGRES_URL='postgresql://fake:fake@127.0.0.1:29444/test',
                            JWT_ACCESS_SECRET='j' * 32, CSRF_SECRET='c' * 32)

    def test_base_preserves_disabled_flags_and_two_tables(self):
        value = profile_contract(BASE)
        self.assertEqual(len(value['migrations']), 2)
        self.assertEqual(value['tables'], ['assets.assets', 'auth.accounts'])
        self.assertEqual(set(value['flags']), set(FEATURES))
        self.assertTrue(all(v == 'false' for v in value['flags'].values()))

    def test_extended_keeps_imports_off_and_schema_complete(self):
        value = profile_contract(EXTENDED)
        self.assertEqual(len(value['migrations']), 7)
        self.assertEqual(len(set(value['migrations'])), 7)
        for key in FEATURES:
            self.assertEqual(value['flags'][key], 'false' if 'IMPORT' in key else 'true')
        self.assertEqual(value['tables'], sorted(value['tables']))
        self.assertIn('assets.saved_filters', value['tables'])
        self.assertIn('assets.import_receipts', value['tables'])

    def test_unknown_profile_rejected(self):
        for name in ('', 'BASE', None, {}, True):
            with self.subTest(name=name), self.assertRaises(ValueError):
                profile_contract(name)

    def test_returned_contract_is_not_shared(self):
        value = profile_contract(EXTENDED)
        value['flags'].clear()
        value['migrations'].clear()
        value['tables'].clear()
        self.assertEqual(len(profile_contract(EXTENDED)['flags']), len(FEATURES))
        self.assertEqual(len(profile_contract(EXTENDED)['migrations']), 7)
        self.assertEqual(len(profile_contract(EXTENDED)['tables']), 4)

    def test_all_conflicting_overrides_rejected_without_mutation(self):
        for name in (BASE, EXTENDED):
            for key, expected in profile_contract(name)['flags'].items():
                private = dict(self.private, **{key: 'false' if expected == 'true' else 'true'})
                original = dict(private)
                with self.subTest(profile=name, key=key), self.assertRaisesRegex(
                        ValueError, '^Feature override conflicts with selected profile$'):
                    profile_environment(name, private, {})
                self.assertEqual(private, original)

    def test_environment_security_preserved_and_input_not_mutated(self):
        original = dict(self.private)
        env = profile_environment(EXTENDED, self.private, {'NODE_OPTIONS': 'unsafe'})
        self.assertEqual(self.private, original)
        self.assertNotIn('NODE_OPTIONS', env)
        self.assertEqual(env['CSRF_ENABLED'], 'true')
        self.assertEqual(env['CSRF_COOKIE_SECURE'], 'true')
        self.assertEqual(env['REQUEST_FRESHNESS_ENABLED'], 'true')
        self.assertEqual(env['THROTTLE_LIMIT'], '60')
        self.assertEqual(env['ASSET_IMPORT_ENABLED'], 'false')

    def test_matching_overrides_allowed_and_unknown_settings_refused(self):
        private = dict(self.private, ASSET_DATES_ENABLED='true')
        self.assertEqual(profile_environment(EXTENDED, private, {})['ASSET_DATES_ENABLED'], 'true')
        private['UNSAFE_SECRET_OVERRIDE'] = 'never-echo'
        with self.assertRaisesRegex(ValueError, '^Unsupported private environment fields$'):
            profile_environment(EXTENDED, private, {})

    def test_invalid_private_type(self):
        for value in (None, [], 'private'):
            with self.assertRaisesRegex(ValueError, '^Invalid private environment$'):
                profile_environment(BASE, value, {})


if __name__ == '__main__':
    unittest.main()
