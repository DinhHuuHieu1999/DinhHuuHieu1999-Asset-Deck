"""Extended profile recovery with injected synthetic command bytes only."""

import json
import unittest
import test_daily_local_recovery as base
from daily_local_profile import EXTENDED, profile_contract
from daily_local_recovery import snapshot, verify_extended_restore


class ExtendedRecoveryTests(unittest.TestCase):
    def setUp(self):
        base.RecoveryTests.setUp(self)
        self.tables = ('\n'.join(profile_contract(EXTENDED)['tables']) + '\n').encode()
        self.rows = {
            'auth.accounts': [{'id': 'owner', 'password_hash': 'never-in-report'}],
            'assets.assets': [{'id': 'asset', 'purchased_on': '2024-02-29',
                               'location': 'Synthetic room %_1', 'checked_on': None}],
            'assets.import_receipts': [],
            'assets.saved_filters': [{'id': 'filter', 'owner_id': 'owner',
                                     'query': {'search': 'Synthetic'}}]}
        original = self.source.runtime.run
        def run(command, **kwargs):
            sql = command[-1]
            if 'json_agg' in sql:
                self.calls.append((command, kwargs))
                table = next(t for t in self.rows if 'FROM ' + t + ')' in sql)
                return json.dumps(self.rows[table]).encode()
            return original(command, **kwargs)
        self.source.runtime.run = run
        self.target.runtime.run = run

    def verify(self, login=lambda db: True):
        return verify_extended_restore(self.source, self.target, self.folder,
                                       lambda: 120, login)

    def test_success_preserves_optional_columns_and_filter_hashes(self):
        result = self.verify()
        self.assertEqual(result['profile'], EXTENDED)
        self.assertEqual(set(result['tables']), set(self.rows))
        self.assertEqual(result['tables']['assets.import_receipts']['records'], 0)
        self.assertNotIn('never-in-report', json.dumps(result))
        self.assertNotIn('Synthetic room', json.dumps(result))
        self.assertTrue((self.folder / 'daily-extended.dump').exists())
        self.assertFalse((self.folder / 'daily-base.dump').exists())
        self.assertTrue(all('row_to_json(t)::text' in c[-1]
                            for c, _ in self.calls if 'json_agg' in c[-1]))

    def test_missing_profile_table_fails_before_dump(self):
        self.tables = b'assets.assets\nauth.accounts\n'
        with self.assertRaisesRegex(ValueError, 'selected profile tables'):
            self.verify()
        self.assertFalse(any('pg_dump' in c for c, _ in self.calls))

    def test_saved_filter_seed_required_before_dump(self):
        self.rows['assets.saved_filters'] = []
        with self.assertRaisesRegex(ValueError, 'seed'):
            self.verify()
        self.assertFalse(any('pg_dump' in c for c, _ in self.calls))

    def test_import_receipts_must_remain_empty(self):
        self.rows['assets.import_receipts'] = [{'owner_id': 'owner', 'request_id': 'req'}]
        with self.assertRaisesRegex(ValueError, 'Import receipts must be empty'):
            self.verify()
        self.assertFalse(any('pg_dump' in c for c, _ in self.calls))

    def test_changed_optional_field_fails_comparison(self):
        original = self.target.runtime.run
        def run(command, **kwargs):
            if 'pg_restore' in command:
                self.rows['assets.assets'][0]['location'] = 'changed'
            return original(command, **kwargs)
        self.target.runtime.run = run
        with self.assertRaisesRegex(ValueError, 'comparison failed'):
            self.verify()
        self.assertTrue((self.folder / 'daily-extended.dump').exists())
        self.assertFalse((self.folder / 'daily-extended-manifest.json').exists())

    def test_login_failure_preserves_dump_without_success(self):
        with self.assertRaisesRegex(ValueError, 'login acceptance failed'):
            self.verify(lambda db: False)
        self.assertTrue((self.folder / 'daily-extended.dump').exists())
        self.assertFalse((self.folder / 'daily-extended-manifest.json').exists())

    def test_arbitrary_or_partial_table_sets_rejected_before_commands(self):
        for tables in (('assets.assets; DROP TABLE auth.accounts',),
                       ('assets.assets',), (), ['auth.accounts', 'assets.assets']):
            with self.subTest(tables=tables), self.assertRaisesRegex(
                    ValueError, '^Unsupported recovery snapshot table set$'):
                snapshot(self.source, tables)
        self.assertEqual(self.calls, [])

    def test_changed_saved_filter_fails_comparison(self):
        original = self.target.runtime.run
        def run(command, **kwargs):
            if 'pg_restore' in command:
                self.rows['assets.saved_filters'][0]['query']['search'] = 'changed'
            return original(command, **kwargs)
        self.target.runtime.run = run
        with self.assertRaisesRegex(ValueError, 'comparison failed'):
            self.verify()
        self.assertFalse((self.folder / 'daily-extended-manifest.json').exists())

    def test_extended_existing_artifact_not_overwritten(self):
        path = self.folder / 'daily-extended.dump'
        path.write_bytes(b'preserve')
        with self.assertRaisesRegex(ValueError, 'artifacts already exist'):
            self.verify()
        self.assertEqual(path.read_bytes(), b'preserve')
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
