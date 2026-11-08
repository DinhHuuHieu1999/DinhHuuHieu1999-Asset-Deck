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

# Explicit mapping: frontend feature names are not derived from backend spelling.
_CLIENT_FLAGS = {
    'ASSET_IMPORT_ENABLED': 'ASSET_DESK_ENABLE_IMPORT',
    'ASSET_IMPORT_V2_ENABLED': 'ASSET_DESK_ENABLE_IMPORT_V2',
    'ASSET_IMPORT_V3_ENABLED': 'ASSET_DESK_ENABLE_IMPORT_V3',
    'ASSET_IMPORT_V4_ENABLED': 'ASSET_DESK_ENABLE_IMPORT_V4',
    'ASSET_DATES_ENABLED': 'ASSET_DESK_ENABLE_ASSET_DATES',
    'ASSET_LOCATION_ENABLED': 'ASSET_DESK_ENABLE_ASSET_LOCATION',
    'ASSET_CHECK_ENABLED': 'ASSET_DESK_ENABLE_ASSET_CHECK',
    'ASSET_EXPORT_V3_ENABLED': 'ASSET_DESK_ENABLE_EXPORT_V3',
    'ASSET_EXPORT_V4_ENABLED': 'ASSET_DESK_ENABLE_EXPORT_V4',
    'ASSET_SELECTION_EXPORT_ENABLED': 'ASSET_DESK_ENABLE_SELECTION_EXPORT',
    'ASSET_SELECTION_EXPORT_V2_ENABLED': 'ASSET_DESK_ENABLE_SELECTION_EXPORT_V2',
    'ASSET_SAVED_FILTERS_ENABLED': 'ASSET_DESK_ENABLE_SAVED_FILTERS',
}


def client_profile_flags(name):
    """Return explicit build metadata, not proof of a compiled release's flags.

    Endpoint selection, artifact provenance and native acceptance remain separate.
    No command is executed and no environment or secret file is read.
    """
    contract = profile_contract(name)
    if (set(_CLIENT_FLAGS) != set(FEATURES)
            or len(set(_CLIENT_FLAGS.values())) != len(_CLIENT_FLAGS)):
        raise ValueError('Daily client feature mapping is incomplete')
    flags = {_CLIENT_FLAGS[key]: value for key, value in contract['flags'].items()}
    flags['ASSET_DESK_ALLOW_LOCAL_HTTP'] = 'false'
    return flags


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

    The launcher uses this helper only with an explicit named profile. Callers
    must separately verify schema, client flags, release identity and storage.
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
