"""Base-profile synthetic backup/restore contract; no commands run on import."""

import hashlib
import json
import re

LIMIT = 64 * 1024 * 1024
TABLES = ('auth.accounts', 'assets.assets')


def snapshot(database):
    """Hash all base-profile columns without persisting account or asset values."""
    database.assert_owned()
    result = {}
    for table in TABLES:
        sql = "SELECT COALESCE(json_agg(t ORDER BY id),'[]'::json)::text FROM (SELECT * FROM " + table + ") t"
        raw = database.runtime.run(['docker', 'exec', database.name, 'psql',
            '-v', 'ON_ERROR_STOP=1', '-U', 'fixture', '-d', 'fixture', '-Atqc', sql])
        if len(raw) > LIMIT:
            raise ValueError('Synthetic snapshot exceeds limit')
        rows = json.loads(raw)
        if type(rows) is not list or any(type(row) is not dict or 'id' not in row for row in rows):
            raise ValueError('Invalid synthetic snapshot')
        canonical = json.dumps(rows, sort_keys=True, separators=(',', ':')).encode('utf-8')
        result[table] = {'records': len(rows), 'sha256': hashlib.sha256(canonical).hexdigest()}
    return result


def verify_base_restore(source, target, folder, remaining, login_check):
    """Restore only into a distinct empty owned synthetic DB; retain all artifacts.

    Caller owns provisioning, stopping writers, deadlines and cleanup. Both DBs
    must use migrations 001/002 only; target must be fresh and unmigrated.
    login_check must authenticate against the restored target, not the source.
    This function is not a daily deployment command and performs no cleanup.
    """
    for db in (source, target):
        if (not re.fullmatch(r'[0-9a-f]{32}', db.identity)
                or db.name != 'asset-daily-' + db.identity):
            raise ValueError('Invalid synthetic recovery identity')
    if not folder.is_absolute() or not folder.is_dir():
        raise ValueError('Absolute existing recovery directory required')
    if source.identity == target.identity:
        raise ValueError('Restore source and target must differ')
    for path in (folder,) + tuple(folder.parents):
        if path.is_symlink() or getattr(path.stat(), 'st_file_attributes', 0) & 1024:
            raise ValueError('Linked recovery directory refused')
    dump_path, manifest = folder / 'daily-base.dump', folder / 'daily-base-manifest.json'
    if dump_path.exists() or manifest.exists():
        raise ValueError('Recovery artifacts already exist')
    remaining()
    source.assert_owned()
    target.assert_owned()
    raw = target.runtime.run(['docker', 'exec', target.name, 'psql', '-U', 'fixture',
        '-d', 'fixture', '-Atqc',
        "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')"])
    if raw.strip() != b'0':
        raise ValueError('Restore target must be empty')
    tables = source.runtime.run(['docker', 'exec', source.name, 'psql',
        '-v', 'ON_ERROR_STOP=1', '-U', 'fixture', '-d', 'fixture', '-Atqc',
        "SELECT schemaname || '.' || tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1"])
    if tables.decode('utf-8').splitlines() != sorted(TABLES):
        raise ValueError('Source must contain exactly the base-profile tables')
    before = snapshot(source)
    if any(item['records'] < 1 for item in before.values()):
        raise ValueError('Synthetic account and asset seed required')
    remaining()
    source.assert_owned()
    dump = source.runtime.run(['docker', 'exec', source.name, 'pg_dump',
                               '-U', 'fixture', '-d', 'fixture', '-Fc'])
    if not dump.startswith(b'PGDMP') or len(dump) > LIMIT:
        raise ValueError('Invalid synthetic dump')
    with dump_path.open('xb') as stream:
        stream.write(dump)
    digest = hashlib.sha256(dump).hexdigest()
    remaining()
    target.assert_owned()
    target.runtime.run(['docker', 'exec', '-i', target.name, 'pg_restore',
        '--exit-on-error', '--no-owner', '--no-privileges', '-U', 'fixture',
        '-d', 'fixture'], data=dump)
    if snapshot(target) != before or snapshot(source) != before:
        raise ValueError('Synthetic restore comparison failed')
    remaining()
    if login_check(target) is not True:
        raise ValueError('Restored login acceptance failed')
    remaining()
    result = {'status': 'completed', 'profile': 'base-001-002-only',
              'dumpSha256': digest, 'tables': before, 'restoredLogin': True,
              'nativeAcceptance': 'pending'}
    with manifest.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    return result
