"""Explicit source-only daily profiles; no migration or process execution."""

from daily_local_environment import FEATURES, backend_environment

BASE = 'base'
EXTENDED = 'inventory-with-saved-filters'
_MIGRATIONS = (
    '001-auth-accounts.sql', '002-assets.sql', '003-asset-import.sql',
    '004-asset-dates.sql', '005-asset-location.sql', '006-asset-check.sql',
    '007-asset-saved-filters.sql')
_ENABLED = frozenset((
    'ASSET_DATES_ENABLED', 'ASSET_LOCATION_ENABLED', 'ASSET_EXPORT_V3_ENABLED',
    'ASSET_SELECTION_EXPORT_ENABLED', 'ASSET_CHECK_ENABLED',
    'ASSET_SELECTION_EXPORT_V2_ENABLED', 'ASSET_EXPORT_V4_ENABLED',
    'ASSET_SAVED_FILTERS_ENABLED'))


def profile_contract(name):
    """Return fresh flags/schema metadata; never infer or apply a profile."""
    if type(name) is not str or name not in (BASE, EXTENDED):
        raise ValueError('Unknown daily runtime profile')
    extended = name == EXTENDED
    return {
        'name': name,
        'flags': {key: 'true' if extended and key in _ENABLED else 'false'
                  for key in FEATURES},
        'migrations': list(_MIGRATIONS if extended else _MIGRATIONS[:2]),
        'tables': ['assets.assets', 'assets.import_receipts',
                   'assets.saved_filters', 'auth.accounts'] if extended else
                  ['assets.assets', 'auth.accounts'],
    }


def profile_environment(name, private, system):
    """Build secure environment, rejecting feature overrides outside the contract.

    This helper is not wired into the launcher. Callers must separately verify
    schema, client flags, release identity and private storage before startup.
    """
    contract = profile_contract(name)
    if type(private) is not dict:
        raise ValueError('Invalid private environment')
    for flag, expected in contract['flags'].items():
        if flag in private and private[flag] != expected:
            raise ValueError('Feature override conflicts with selected profile')
    values = dict(private)
    values.update(contract['flags'])
    return backend_environment(values, system)
