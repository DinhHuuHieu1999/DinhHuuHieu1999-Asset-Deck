"""Explicit-profile synthetic backup/restore contracts; no commands on import."""

import hashlib
import json
import re

LIMIT = 64 * 1024 * 1024
TABLES = ('auth.accounts', 'assets.assets')


def snapshot(database, tables=TABLES):
    """Hash all selected columns; permit only fixed internal profile table sets."""
    from daily_local_profile import EXTENDED, profile_contract
    extended = tuple(profile_contract(EXTENDED)['tables'])
    if type(tables) is not tuple or tables not in (TABLES, extended):
        raise ValueError('Unsupported recovery snapshot table set')
    database.assert_owned()
    result = {}
    for table in tables:
        sql = "SELECT COALESCE(json_agg(t ORDER BY row_to_json(t)::text),'[]'::json)::text FROM (SELECT * FROM " + table + ") t"
        raw = database.runtime.run(['docker', 'exec', database.name, 'psql',
            '-v', 'ON_ERROR_STOP=1', '-U', 'fixture', '-d', 'fixture', '-Atqc', sql])
        if len(raw) > LIMIT:
            raise ValueError('Synthetic snapshot exceeds limit')
        rows = json.loads(raw)
        keys = ('owner_id', 'request_id') if table == 'assets.import_receipts' else ('id',)
        if type(rows) is not list or any(type(row) is not dict or
                                        any(key not in row for key in keys) for row in rows):
            raise ValueError('Invalid synthetic snapshot')
        canonical = json.dumps(rows, sort_keys=True, separators=(',', ':')).encode('utf-8')
        result[table] = {'records': len(rows), 'sha256': hashlib.sha256(canonical).hexdigest()}
    return result


def verify_base_restore(source, target, folder, remaining, login_check, checkpoint=None):
    """Keep the original base-only restore contract and artifact names."""
    return _verify_restore(source, target, folder, remaining, login_check,
                           TABLES, 'base-001-002-only', 'daily-base', TABLES, checkpoint)


def verify_extended_restore(source, target, folder, remaining, login_check, checkpoint=None):
    """Verify the named extended synthetic profile; imports must remain unused.

    No provisioning or cleanup is performed. The login callback must additionally
    verify restored owner-scoped saved filters and optional inventory fields.
    Synthetic acceptance does not certify native UI or daily deployment.
    """
    from daily_local_profile import EXTENDED, profile_contract
    tables = tuple(profile_contract(EXTENDED)['tables'])
    required = ('auth.accounts', 'assets.assets', 'assets.saved_filters')
    return _verify_restore(source, target, folder, remaining, login_check,
                           tables, EXTENDED, 'daily-extended', required, checkpoint)


def _verify_restore(source, target, folder, remaining, login_check,
                    expected_tables, profile, artifact, required, checkpoint=None):
    """Restore only into a distinct empty owned synthetic DB; retain all artifacts.

    Caller owns provisioning, stopping writers, deadlines and cleanup. Both DBs
    must match the selected fixed table set; target must be fresh and unmigrated.
    login_check must authenticate against the restored target, not the source.
    This function is not a daily deployment command and performs no cleanup.
    """
    mark = checkpoint or (lambda stage: None)
    mark('restore-preflight')
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
    dump_path, manifest = folder / (artifact + '.dump'), folder / (artifact + '-manifest.json')
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
    if tables.decode('utf-8').splitlines() != sorted(expected_tables):
        raise ValueError('Source must contain exactly the base-profile tables' if artifact == 'daily-base'
                         else 'Source must contain exactly the selected profile tables')
    mark('source-snapshot')
    before = snapshot(source, expected_tables)
    if any(before[table]['records'] < 1 for table in required):
        raise ValueError('Required synthetic profile seed is missing')
    if artifact == 'daily-extended' and before['assets.import_receipts']['records'] != 0:
        raise ValueError('Import receipts must be empty for the imports-disabled profile')
    remaining()
    source.assert_owned()
    mark('dump-create')
    dump = source.runtime.run(['docker', 'exec', source.name, 'pg_dump',
                               '-U', 'fixture', '-d', 'fixture', '-Fc'])
    if not dump.startswith(b'PGDMP') or len(dump) > LIMIT:
        raise ValueError('Invalid synthetic dump')
    with dump_path.open('xb') as stream:
        stream.write(dump)
    digest = hashlib.sha256(dump).hexdigest()
    remaining()
    target.assert_owned()
    mark('dump-restore')
    target.runtime.run(['docker', 'exec', '-i', target.name, 'pg_restore',
        '--exit-on-error', '--no-owner', '--no-privileges', '-U', 'fixture',
        '-d', 'fixture'], data=dump)
    mark('restore-compare')
    if snapshot(target, expected_tables) != before or snapshot(source, expected_tables) != before:
        raise ValueError('Synthetic restore comparison failed')
    remaining()
    mark('restored-login')
    if login_check(target) is not True:
        raise ValueError('Restored login acceptance failed')
    remaining()
    result = {'status': 'completed', 'profile': profile,
              'dumpSha256': digest, 'tables': before, 'restoredLogin': True,
              'nativeAcceptance': 'pending'}
    mark('success-manifest')
    with manifest.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    return result
