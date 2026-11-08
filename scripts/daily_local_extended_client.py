"""Synthetic extended recovery checks using ordinary HTTPS/auth/CSRF routes."""

from daily_local_fixture_client import SyntheticClient


class ExtendedOwner(SyntheticClient):
    """Retain expected synthetic data privately across source and restored login."""

    def __init__(self, port, remaining, opener=None, populated=True):
        super().__init__(port, remaining, opener)
        self.fields = {
            'dates': {'purchasedOn': '2024-02-29' if populated else None,
                      'warrantyExpiresOn': '2027-02-28' if populated else None},
            'location': {'location': 'Synthetic room %_1' if populated else None},
            'check-date': {'lastCheckedOn': '2024-03-01' if populated else None}}
        self.query = dict(q='Synthetic', status='stored', category='fixture',
                          sort='checked_asc', locationMode='all', location='',
                          warranty='all', asOf='', checkMode='all', checkBefore='',
                          checkOnOrAfter='')
        self.asset_id = None
        self.saved = None

    def create_synthetic_asset(self):
        """Write one synthetic asset and a saved query with shared edit versions."""
        asset_id = super().create_synthetic_asset()
        for suffix, fields in self.fields.items():
            path = '/api/v1/assets/' + asset_id + '/' + suffix
            current = self.request(path)
            result = self.request(path, dict(fields, version=current['version']), method='PUT')
            self._assert_fields(result, fields)
        self.saved = self.request('/api/v1/inventory-saved-filters',
                                  dict(name='Synthetic saved view', schemaVersion=1,
                                       query=self.query), expected=201)
        if (type(self.saved) is not dict or not isinstance(self.saved.get('id'), str)
                or self.saved.get('query') != self.query):
            raise RuntimeError('Synthetic saved filter creation mismatch')
        self.asset_id = asset_id
        return asset_id

    @staticmethod
    def _assert_fields(result, expected):
        if type(result) is not dict or any(key not in result or result[key] != value
                                          for key, value in expected.items()):
            raise RuntimeError('Synthetic optional fields mismatch')

    def login_and_assert_asset(self, asset_id):
        """Check full optional values and this owner's saved query after login."""
        if asset_id != self.asset_id or self.saved is None:
            raise RuntimeError('Synthetic extended seed identity missing')
        super().login_and_assert_asset(asset_id)
        for suffix, fields in self.fields.items():
            self._assert_fields(self.request('/api/v1/assets/' + asset_id + '/' + suffix), fields)
        items = self.request('/api/v1/inventory-saved-filters').get('items')
        if items != [self.saved]:
            raise RuntimeError('Synthetic saved filter restore mismatch')


class ExtendedClient:
    """Two independent synthetic accounts; no owner credential or row is reported."""

    def __init__(self, port, remaining, owner_factory=ExtendedOwner):
        self.owners = [owner_factory(port, remaining, populated=value)
                       for value in (True, False)]
        self.ids = None

    def create_synthetic_asset(self):
        """Seed populated/null cases and ensure owner-scoped reads before backup."""
        self.ids = [owner.create_synthetic_asset() for owner in self.owners]
        if self.ids[0] == self.ids[1]:
            raise RuntimeError('Synthetic owner asset identities must differ')
        self._check(self.ids[0])
        return self.ids[0]

    def _check(self, asset_id):
        if self.ids is None or asset_id != self.ids[0]:
            raise RuntimeError('Synthetic extended identity mismatch')
        for index, owner in enumerate(self.owners):
            owner.login_and_assert_asset(self.ids[index])
            other_id = self.ids[1 - index]
            for suffix in ('dates', 'location', 'check-date'):
                owner.request('/api/v1/assets/' + other_id + '/' + suffix, expected=404)

    def login_and_assert_asset(self, asset_id):
        """Recheck both accounts through the restored target's HTTPS endpoint."""
        self._check(asset_id)
