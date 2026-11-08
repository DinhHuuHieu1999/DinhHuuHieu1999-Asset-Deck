"""Extended HTTPS assertions with fake responses only; no network or TLS reads."""

import unittest
from daily_local_extended_client import ExtendedOwner, ExtendedClient


class OwnerTests(unittest.TestCase):
    def make_owner(self, populated=True):
        owner = ExtendedOwner(29443, lambda: 120, opener=object(), populated=populated)
        self.calls = []
        saved = dict(id='saved-id', name='Synthetic saved view', schemaVersion=1,
                     version=1, query=owner.query)
        def request(path, data=None, expected=200, method=None):
            self.calls.append((path, data, expected, method))
            if path.endswith('csrf-token'): return {'token': 'synthetic'}
            if '/auth/' in path: return {'accessToken': 'synthetic'}
            if path == '/api/v1/assets':
                if data is not None: return dict(owner.asset, id='asset-id')
                return {'items': [dict(owner.asset, id='asset-id')]}
            if path.endswith('inventory-saved-filters'):
                return dict(saved) if data is not None else {'items': [dict(saved)]}
            for suffix, fields in owner.fields.items():
                if path.endswith('/' + suffix): return dict(fields, version=1)
            raise AssertionError('Unexpected route')
        owner.request = request
        return owner

    def test_seed_put_fields_and_normal_saved_filter_post(self):
        owner = self.make_owner()
        asset_id = owner.create_synthetic_asset()
        owner.login_and_assert_asset(asset_id)
        puts = [data for _, data, _, method in self.calls if method == 'PUT']
        self.assertEqual(len(puts), 3)
        self.assertEqual(puts[0]['purchasedOn'], '2024-02-29')
        self.assertEqual(puts[1]['location'], 'Synthetic room %_1')
        self.assertEqual(puts[2]['lastCheckedOn'], '2024-03-01')
        self.assertTrue(all(data['version'] == 1 for data in puts))

    def test_null_fields_are_explicit_and_verified(self):
        owner = self.make_owner(False)
        owner.create_synthetic_asset()
        owner.login_and_assert_asset('asset-id')
        self.assertTrue(all(value is None for fields in owner.fields.values()
                            for value in fields.values()))

    def test_changed_optional_value_rejected(self):
        owner = self.make_owner()
        owner.create_synthetic_asset()
        original = owner.request
        def request(path, *args, **kwargs):
            if path.endswith('/location'): return {'location': 'changed', 'version': 4}
            return original(path, *args, **kwargs)
        owner.request = request
        with self.assertRaisesRegex(RuntimeError, 'optional fields mismatch'):
            owner.login_and_assert_asset('asset-id')

    def test_foreign_saved_filter_in_list_rejected(self):
        owner = self.make_owner()
        owner.create_synthetic_asset()
        original = owner.request
        def request(path, *args, **kwargs):
            if path.endswith('inventory-saved-filters'):
                return {'items': [owner.saved, dict(owner.saved, id='foreign')]}
            return original(path, *args, **kwargs)
        owner.request = request
        with self.assertRaisesRegex(RuntimeError, 'saved filter restore mismatch'):
            owner.login_and_assert_asset('asset-id')

    def test_missing_null_key_not_treated_as_null(self):
        with self.assertRaisesRegex(RuntimeError, 'optional fields mismatch'):
            ExtendedOwner._assert_fields({}, {'location': None})


class TwoOwnerTests(unittest.TestCase):
    def test_two_accounts_checked_and_foreign_reads_expect_404(self):
        owners = []
        class Owner:
            def __init__(self, *args, populated):
                self.identity = str(len(owners))
                self.calls = []
                owners.append(self)
            def create_synthetic_asset(self): return self.identity
            def login_and_assert_asset(self, identity):
                if identity != self.identity: raise AssertionError('Wrong owner identity')
            def request(self, path, expected): self.calls.append((path, expected))
        client = ExtendedClient(29443, lambda: 120, Owner)
        identity = client.create_synthetic_asset()
        client.login_and_assert_asset(identity)
        self.assertEqual([len(o.calls) for o in owners], [6, 6])
        self.assertTrue(all(status == 404 for o in owners for _, status in o.calls))
        self.assertTrue(all('/1/' in path for path, _ in owners[0].calls))
        with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
            client.login_and_assert_asset('wrong')
