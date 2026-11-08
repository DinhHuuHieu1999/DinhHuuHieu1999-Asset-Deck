"""Internal synthetic dates database verification; never accepts operator targets."""
import hashlib
import json
import re
import time


def snapshot(runtime, name, database):
    """Digest every asset column, including nullable dates and shared versions."""
    raw = runtime.run(['docker', 'exec', name, 'psql', '-v', 'ON_ERROR_STOP=1',
        '-U', 'fixture', '-d', database, '-Atqc',
        "SELECT COALESCE(json_agg(t ORDER BY id),'[]'::json)::text FROM (SELECT * FROM assets.assets) t"])
    if len(raw) > 4 * 1024 * 1024:
        raise ValueError('Oversized synthetic snapshot')
    rows = json.loads(raw)
    if (not isinstance(rows, list) or len(rows) < 4 or any(not isinstance(row, dict) or
        not {'id', 'owner_id', 'version', 'purchased_on', 'warranty_expires_on'}.issubset(row) for row in rows)):
        raise ValueError('Incomplete synthetic snapshot')
    canonical = json.dumps(rows, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return {'records': len(rows), 'sha256': hashlib.sha256(canonical).hexdigest()}


def verify(runtime, name, database, identity, folder, client):
    """Retain dump and verify restart/restore only inside the owned fixture."""
    if (not isinstance(identity, str) or not re.fullmatch(r'[0-9a-f]{32}', identity) or
        name != 'asset-dates-' + identity or database != 'asset_dates_fixture_' + identity[:12]):
        raise client.Refusal('Invalid dates recovery identity')
    client.assert_owned(runtime, name, identity)
    before = snapshot(runtime, name, database)
    dump = runtime.run(['docker', 'exec', name, 'pg_dump', '-U', 'fixture', '-d', database, '-Fc'])
    if not dump.startswith(b'PGDMP') or len(dump) > 64 * 1024 * 1024:
        raise client.Refusal('Invalid synthetic database dump')
    with (folder / 'dates-database.dump').open('xb') as target:
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
        raise client.Refusal('Dates changed after restart')
    restored = database + '_restored'
    runtime.run(['docker', 'exec', name, 'createdb', '-U', 'fixture', restored])
    runtime.run(['docker', 'exec', '-i', name, 'pg_restore', '--exit-on-error', '--no-owner',
        '--no-privileges', '-U', 'fixture', '-d', restored], data=dump)
    if snapshot(runtime, name, restored) != before:
        raise client.Refusal('Dates restore comparison failed')
    with (folder / 'dates-recovery-result.json').open('x', encoding='utf-8') as target:
        json.dump({'status': 'completed', 'restart': True, 'restore': True, **before}, target, indent=2)
