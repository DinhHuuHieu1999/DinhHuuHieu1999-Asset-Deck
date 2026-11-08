"""Explicit backend environment policy; never forward agent/shell injection flags."""

from urllib.parse import urlsplit


FEATURES = ('ASSET_IMPORT_ENABLED', 'ASSET_DATES_ENABLED', 'ASSET_IMPORT_V2_ENABLED',
            'ASSET_LOCATION_ENABLED', 'ASSET_EXPORT_V3_ENABLED', 'ASSET_IMPORT_V3_ENABLED',
            'ASSET_SELECTION_EXPORT_ENABLED', 'ASSET_CHECK_ENABLED',
            'ASSET_SELECTION_EXPORT_V2_ENABLED', 'ASSET_EXPORT_V4_ENABLED',
            'ASSET_IMPORT_V4_ENABLED', 'ASSET_SAVED_FILTERS_ENABLED')
SETTINGS = ('AUTH_POSTGRES_URL', 'JWT_ACCESS_SECRET', 'CSRF_SECRET',
            'JWT_ACCESS_EXPIRES_IN', 'AUTH_POSTGRES_POOL_SIZE',
            'AUTH_POSTGRES_CONNECT_TIMEOUT_MS', 'AUTH_POSTGRES_STATEMENT_TIMEOUT_MS')


def backend_environment(private, system):
    """Construct a fresh environment from reviewed values, never echoing failures."""
    if type(private) is not dict or set(private) - set(SETTINGS + FEATURES):
        raise ValueError('Unsupported private environment fields')
    if any(not isinstance(value, str) or '\x00' in value for value in private.values()):
        raise ValueError('Invalid private environment values')
    for name in ('JWT_ACCESS_SECRET', 'CSRF_SECRET'):
        if len(private.get(name, '')) < 32:
            raise ValueError('Required private secret is missing or too short')
    try:
        url = urlsplit(private.get('AUTH_POSTGRES_URL', ''))
        if (url.scheme not in ('postgres', 'postgresql')
                or url.hostname not in ('localhost', '127.0.0.1')
                or url.port is None or not 1024 <= url.port <= 65535
                or not url.path.strip('/') or url.fragment):
            raise ValueError()
    except ValueError:
        raise ValueError('A separate loopback PostgreSQL URL is required') from None
    env = {name: value for name, value in system.items()
           if name.upper() in ('SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP', 'USERPROFILE',
                               'APPDATA', 'LOCALAPPDATA')}
    env.update(private)
    for feature in FEATURES:
        value = private.get(feature, 'false')
        if value not in ('true', 'false'):
            raise ValueError('Invalid feature flag')
        env[feature] = value
    env.update(NODE_ENV='production', CSRF_ENABLED='true', CSRF_COOKIE_SECURE='true',
               AUTH_EXPOSE_RESET_TOKEN='false', REQUEST_FRESHNESS_ENABLED='true',
               REQUEST_TIMESTAMP_HEADER='x-request-timestamp', REQUEST_MAX_AGE_MS='300000',
               THROTTLE_TTL_MS='60000', THROTTLE_LIMIT='60')
    return env
