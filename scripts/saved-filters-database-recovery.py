"""Synthetic saved-filter database restart/restore checks; no operator targets."""
import hashlib
import json
import re
import time


def snapshot(runtime, name, database):
    """Hash all saved definitions, assets and owner IDs without logging private text."""
    sql = """SELECT json_build_object(
      'filters', (SELECT COALESCE(json_agg(t ORDER BY id),'[]'::json) FROM (SELECT * FROM assets.saved_filters) t),
      'assets', (SELECT COALESCE(json_agg(t ORDER BY id),'[]'::json) FROM (SELECT * FROM assets.assets) t),
      'owners', (SELECT COALESCE(json_agg(id ORDER BY id),'[]'::json) FROM auth.accounts))::text"""
    raw = runtime.run(['docker', 'exec', name, 'psql', '-v', 'ON_ERROR_STOP=1',
                       '-U', 'fixture', '-d', database, '-Atqc', sql])
    if len(raw) > 4 * 1024 * 1024:
        raise ValueError('Oversized synthetic snapshot')
    value = json.loads(raw)
    if not isinstance(value, dict) or set(value) != {'filters', 'assets', 'owners'}:
        raise ValueError('Incomplete synthetic snapshot')
    filters, assets, owners = value['filters'], value['assets'], value['owners']
    required = {'id', 'owner_id', 'name', 'query_schema_version', 'query', 'version', 'created_at', 'updated_at'}
    if (not isinstance(filters, list) or not filters or not isinstance(assets, list) or not assets or
            not isinstance(owners, list) or len(set(owners)) < 2 or
            any(not isinstance(row, dict) or not required.issubset(row) or
                row['owner_id'] not in owners or not isinstance(row['query'], dict) or
                type(row['version']) is not int or row['version'] < 1 for row in filters) or
            any(not isinstance(row, dict) or not {'id', 'owner_id', 'version'}.issubset(row) or
                row['owner_id'] not in owners for row in assets) or
            len({row['owner_id'] for row in filters}) < 2):
        raise ValueError('Incomplete synthetic rows or owner coverage')
    canonical = json.dumps(value, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return {'definitions': len(filters), 'assets': len(assets),
            'owners': len(owners), 'sha256': hashlib.sha256(canonical).hexdigest()}


def verify(runtime, name, database, identity, folder, client):
    """Retain an exclusive dump and compare restart and fresh-database restoration."""
    if (not isinstance(identity, str) or not re.fullmatch(r'[0-9a-f]{32}', identity) or
            name != 'asset-saved-filters-' + identity or
            database != 'asset_saved_filters_fixture_' + identity[:12]):
        raise client.Refusal('Invalid saved filters recovery identity')
    dump_path = folder / 'saved-filters-database.dump'
    result_path = folder / 'saved-filters-recovery-result.json'
    if dump_path.exists() or result_path.exists():
        raise client.Refusal('Recovery evidence already exists')
    client.assert_owned(runtime, name, identity)
    before = snapshot(runtime, name, database)
    dump = runtime.run(['docker', 'exec', name, 'pg_dump', '-U', 'fixture', '-d', database, '-Fc'])
    if not dump.startswith(b'PGDMP') or len(dump) > 64 * 1024 * 1024:
        raise client.Refusal('Invalid synthetic database dump')
    with dump_path.open('xb') as target:
        target.write(dump)
    client.assert_owned(runtime, name, identity)
    runtime.run(['docker', 'stop', '--time', '10', name])
    client.assert_owned(runtime, name, identity)
    runtime.run(['docker', 'start', name])
    until = min(runtime.deadline, time.monotonic() + 30)
    while True:
        try:
            raw = runtime.run(['docker', 'exec', name, 'psql', '-U', 'fixture', '-d', database,
                               '-Atqc', "SELECT current_database() || '|' || current_user"])
        except client.Refusal:
            if time.monotonic() >= until:
                raise client.Refusal('Restart readiness deadline exceeded') from None
            time.sleep(0.2)
            continue
        if raw.decode().strip() != database + '|fixture':
            raise client.Refusal('Restart database identity mismatch')
        break
    client.assert_owned(runtime, name, identity)
    if snapshot(runtime, name, database) != before:
        raise client.Refusal('Saved filters changed after restart')
    restored = database + '_restored'
    client.assert_owned(runtime, name, identity)
    runtime.run(['docker', 'exec', name, 'createdb', '-U', 'fixture', restored])
    runtime.run(['docker', 'exec', '-i', name, 'pg_restore', '--exit-on-error', '--no-owner',
                 '--no-privileges', '-U', 'fixture', '-d', restored], data=dump)
    if snapshot(runtime, name, restored) != before:
        raise client.Refusal('Saved filters restore comparison failed')
    with result_path.open('x', encoding='utf-8') as target:
        json.dump(dict(status='completed', databaseRestart=True, databaseRestore=True,
                       backendRestart=False, **before), target, indent=2)
