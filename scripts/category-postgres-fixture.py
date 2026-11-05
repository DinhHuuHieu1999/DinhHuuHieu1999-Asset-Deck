"""Explicit synthetic repository acceptance; import has no runtime side effects."""
import argparse
import importlib.util
import json
from pathlib import Path
import secrets
import shutil
import time

_spec = importlib.util.spec_from_file_location('category_shared_lifecycle', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)
FILES = ('backend/migrations/001-auth-accounts.sql', 'backend/migrations/002-assets.sql',
         'backend/src/domains/assets/assets-category.postgres.spec.ts',
         'backend/src/domains/assets/assets.repository.ts', 'backend/src/domains/assets/assets.dto.ts',
         'backend/node_modules/jest/bin/jest.js')


OVERVIEW_FILES = (FILES[0], FILES[1],
                  'backend/src/domains/assets/assets-overview.postgres.spec.ts',
                  FILES[3], 'backend/src/domains/assets/asset-overview.ts', FILES[-1])


DATES_FILES = (FILES[0], FILES[1],
               'backend/src/domains/assets/assets-dates.postgres.spec.ts',
               FILES[3], 'backend/src/domains/assets/asset-dates.repository.ts',
               'backend/migrations/004-asset-dates.sql', FILES[-1])


EXPORT_V2_FILES = (FILES[0], FILES[1],
                   'backend/src/domains/assets/assets-export-v2.postgres.spec.ts',
                   FILES[3], 'backend/src/domains/assets/asset-dates.repository.ts',
                   'backend/src/domains/assets/asset-export-v2.ts',
                   'backend/src/domains/assets/asset-export.ts',
                   'backend/src/domains/assets/asset-dates.ts',
                   'backend/migrations/004-asset-dates.sql', FILES[-1])


EXPORT_V3_FILES = EXPORT_V2_FILES[:2] + (
    'backend/src/domains/assets/assets-export-v3.postgres.spec.ts',
) + EXPORT_V2_FILES[3:-1] + (
    'backend/src/domains/assets/asset-export-v3.repository.ts',
    'backend/src/domains/assets/asset-export-v3.ts',
    'backend/src/domains/assets/asset-location.ts',
    'backend/migrations/005-asset-location.sql', FILES[-1],
)


WARRANTY_FILES = (FILES[0], FILES[1],
                  'backend/src/domains/assets/assets-warranty.postgres.spec.ts',
                  FILES[3], 'backend/src/domains/assets/asset-dates.repository.ts',
                  'backend/src/domains/assets/asset-warranty.ts',
                  'backend/src/domains/assets/asset-warranty.dto.ts',
                  'backend/src/domains/assets/asset-dates.ts',
                  'backend/migrations/004-asset-dates.sql', FILES[-1])


WARRANTY_OVERVIEW_FILES = WARRANTY_FILES[:2] + (
    'backend/src/domains/assets/assets-warranty-overview.postgres.spec.ts',
) + WARRANTY_FILES[3:-1] + (
    'backend/src/domains/assets/asset-warranty-overview.ts', FILES[-1],
)


IMPORT_V2_FILES = (FILES[0], FILES[1],
    'backend/src/domains/assets/asset-import-v2.postgres.spec.ts',
    'backend/src/domains/assets/asset-import-v2.repository.ts',
    'backend/src/domains/assets/asset-import-v2.ts',
    'backend/src/domains/assets/asset-import.repository.ts',
    'backend/src/domains/assets/asset-import.ts',
    'backend/src/domains/assets/asset-dates.ts',
    'backend/src/domains/assets/assets.dto.ts',
    'backend/migrations/003-asset-import.sql',
    'backend/migrations/004-asset-dates.sql', FILES[-1])


IMPORT_V3_FILES = IMPORT_V2_FILES[:2] + (
    'backend/src/domains/assets/asset-import-v3.postgres.spec.ts',
    'backend/src/domains/assets/asset-import-v3.repository.ts',
    'backend/src/domains/assets/asset-import-v3.ts',
) + IMPORT_V2_FILES[5:-1] + (
    'backend/src/domains/assets/asset-location.ts',
    'backend/src/domains/assets/asset-import-v2.repository.ts',
    'backend/src/domains/assets/asset-import-v2.ts',
    'backend/migrations/005-asset-location.sql', FILES[-1],
)



LOCATION_FILES = (FILES[0], FILES[1],
    'backend/src/domains/assets/asset-location.postgres.spec.ts',
    FILES[3], 'backend/src/domains/assets/asset-location.repository.ts',
    'backend/src/domains/assets/asset-location.ts',
    'backend/src/domains/assets/asset-location-overview.ts',
    'backend/src/domains/assets/asset-dates.repository.ts',
    'backend/src/domains/assets/asset-warranty.ts',
    'backend/migrations/004-asset-dates.sql',
    'backend/migrations/005-asset-location.sql', FILES[-1])


LOCATION_OVERVIEW_FILES = tuple(name.replace('asset-location.postgres.spec.ts', 'asset-location-overview.postgres.spec.ts') for name in LOCATION_FILES)


SORT_FILES = LOCATION_FILES[:2] + (
    'backend/src/domains/assets/asset-sort.postgres.spec.ts',
) + LOCATION_FILES[3:-1] + (
    'backend/src/domains/assets/asset-sort.ts',
    'backend/src/domains/assets/assets.dto.ts', FILES[-1],
)



SELECTION_EXPORT_FILES = EXPORT_V3_FILES[:2] + (
    'backend/src/domains/assets/asset-selection-export.postgres.spec.ts',
) + EXPORT_V3_FILES[3:-1] + (
    'backend/src/domains/assets/asset-selection-export.repository.ts',
    'backend/src/domains/assets/asset-selection-export.ts',
    'backend/src/domains/assets/asset-sort.ts',
    'backend/src/domains/assets/asset-warranty.ts', FILES[-1],
)


SERIAL_FILES = (FILES[0], FILES[1],
    'backend/src/domains/assets/asset-serial.postgres.spec.ts',
    FILES[3], 'backend/src/domains/assets/assets.dto.ts',
    'backend/src/domains/assets/asset-sort.ts',
    'backend/src/domains/assets/asset-overview.ts',
    'backend/src/domains/assets/asset-export.ts', FILES[-1])


DETAILS_FILES = tuple(name.replace('asset-serial.postgres.spec.ts', 'asset-details.postgres.spec.ts') for name in SERIAL_FILES)


CHECK_FILES = LOCATION_FILES[:2] + (
    'backend/src/domains/assets/asset-check.postgres.spec.ts',
) + LOCATION_FILES[3:-1] + (
    'backend/src/domains/assets/asset-check.repository.ts',
    'backend/src/domains/assets/asset-check.ts',
    'backend/migrations/003-asset-import.sql',
    'backend/migrations/006-asset-check.sql', FILES[-1],
)


CHECK_OVERVIEW_FILES = CHECK_FILES[:2] + ('backend/src/domains/assets/asset-check-overview.postgres.spec.ts',) + CHECK_FILES[3:-1] + ('backend/src/domains/assets/asset-check-overview.ts', CHECK_FILES[-1])


SELECTION_EXPORT_V2_FILES = SELECTION_EXPORT_FILES[:2] + (
    'backend/src/domains/assets/asset-selection-export-v2.postgres.spec.ts',
) + SELECTION_EXPORT_FILES[3:-1] + (
    'backend/src/domains/assets/asset-selection-export-v2.repository.ts',
    'backend/src/domains/assets/asset-selection-export-v2.ts',
    'backend/src/domains/assets/asset-check.ts',
    'backend/migrations/003-asset-import.sql',
    'backend/migrations/006-asset-check.sql', FILES[-1],
)


def profile_settings(profile):
    """Only fixed source-owned profiles may choose a suite or fixture identity."""
    if profile == 'selection-export-v2':
        return SELECTION_EXPORT_V2_FILES, 'asset-selection-v2-', 'asset_selection_v2_fixture_', 'ASSET_SELECTION_V2', 'isolated-selection-v2', 'asset_selection_v2_fixture_identity'
    if profile == 'check-overview':
        return CHECK_OVERVIEW_FILES, 'asset-check-overview-', 'asset_check_overview_fixture_', 'ASSET_CHECK_OVERVIEW', 'isolated-check-overview-v1', 'asset_check_overview_fixture_identity'
    if profile == 'check':
        return CHECK_FILES, 'asset-check-', 'asset_check_fixture_', 'ASSET_CHECK', 'isolated-check-v1', 'asset_check_fixture_identity'
    if profile == 'details':
        return DETAILS_FILES, 'asset-details-', 'asset_details_fixture_', 'ASSET_DETAILS', 'isolated-details-v1', 'asset_details_fixture_identity'
    if profile == 'serial':
        return SERIAL_FILES, 'asset-serial-', 'asset_serial_fixture_', 'ASSET_SERIAL', 'isolated-serial-v1', 'asset_serial_fixture_identity'
    if profile == 'selection-export':
        return SELECTION_EXPORT_FILES, 'asset-selection-export-', 'asset_selection_export_fixture_', 'ASSET_SELECTION_EXPORT', 'isolated-selection-export-v1', 'asset_selection_export_fixture_identity'
    if profile == 'sort':
        return SORT_FILES, 'asset-sort-', 'asset_sort_fixture_', 'ASSET_SORT', 'isolated-sort-v1', 'asset_sort_fixture_identity'
    if profile == 'export-v3':
        return EXPORT_V3_FILES, 'asset-export-v3-', 'asset_export_v3_fixture_', 'ASSET_EXPORT_V3', 'isolated-export-v3-v1', 'asset_export_v3_fixture_identity'
    if profile == 'location-overview':
        return LOCATION_OVERVIEW_FILES, 'asset-location-overview-', 'asset_location_overview_fixture_', 'ASSET_LOCATION_OVERVIEW', 'isolated-location-overview-v1', 'asset_location_overview_fixture_identity'
    if profile == 'location':
        return LOCATION_FILES, 'asset-location-', 'asset_location_fixture_', 'ASSET_LOCATION', 'isolated-location-v1', 'asset_location_fixture_identity'
    if profile == 'import-v3':
        return IMPORT_V3_FILES, 'asset-import-v3-', 'asset_import_v3_fixture_', 'ASSET_IMPORT_V3', 'isolated-import-v3-v1', 'asset_import_v3_fixture_identity'
    if profile == 'import-v2':
        return IMPORT_V2_FILES, 'asset-import-v2-', 'asset_import_v2_fixture_', 'ASSET_IMPORT_V2', 'isolated-import-v2-v1', 'asset_import_v2_fixture_identity'
    if profile == 'category':
        return FILES, 'asset-category-', 'asset_category_fixture_', 'ASSET_CATEGORY', 'isolated-category-v1', 'asset_category_fixture_identity'
    if profile == 'overview':
        return OVERVIEW_FILES, 'asset-overview-', 'asset_overview_fixture_', 'ASSET_OVERVIEW', 'isolated-overview-v1', 'asset_overview_fixture_identity'
    if profile == 'dates':
        return DATES_FILES, 'asset-dates-', 'asset_dates_fixture_', 'ASSET_DATES', 'isolated-dates-v1', 'asset_dates_fixture_identity'
    if profile == 'export-v2':
        return EXPORT_V2_FILES, 'asset-export-v2-', 'asset_export_v2_fixture_', 'ASSET_EXPORT_V2', 'isolated-export-v2-v1', 'asset_export_v2_fixture_identity'
    if profile == 'warranty-overview':
        return WARRANTY_OVERVIEW_FILES, 'asset-warranty-overview-', 'asset_warranty_overview_fixture_', 'ASSET_WARRANTY_OVERVIEW', 'isolated-warranty-overview-v1', 'asset_warranty_overview_fixture_identity'
    if profile == 'warranty':
        return WARRANTY_FILES, 'asset-warranty-', 'asset_warranty_fixture_', 'ASSET_WARRANTY', 'isolated-warranty-v1', 'asset_warranty_fixture_identity'
    raise client.Refusal('Unknown repository fixture profile')


def preflight(root, args, profile='category'):
    """Refuse missing source, tools or explicit immutable-image opt-in before writes."""
    files = profile_settings(profile)[0]
    if (args.execute_synthetic is not True or not isinstance(args.image, str) or
            len(args.image) != 71 or not args.image.startswith('sha256:') or
            any(c not in '0123456789abcdef' for c in args.image[7:])):
        raise client.Refusal('Explicit synthetic opt-in and immutable image required')
    if any(not (root / name).is_file() for name in files):
        raise client.Refusal('Required source or local Jest missing')
    if any(not shutil.which(name) for name in ('docker', 'node')):
        raise client.Refusal('Required executable missing')


def validate_result(value, expected=4):
    """Skipped, partial or malformed Jest output cannot satisfy live acceptance."""
    if (not isinstance(value, dict) or value.get('success') is not True or
            any(type(value.get(k)) is not int or value[k] != n for k, n in
                (('numPassedTests', expected), ('numTotalTests', expected), ('numFailedTests', 0),
                 ('numPendingTests', 0), ('numRuntimeErrorTestSuites', 0),
                 ('numPassedTestSuites', 1)))):
        raise client.Refusal('Repository assertions incomplete')


def execute(root, args, runtime, profile='category', verification=None):
    """Create one owned database; run once and retain stopped resources/evidence."""
    files, prefix, db_prefix, env_prefix, opt_in, marker_table = profile_settings(profile)
    preflight(root, args, profile)
    if verification is not None and profile != 'dates':
        raise client.Refusal('Recovery verification requires dates profile')
    image = runtime.run(['docker', 'image', 'inspect', '--format', '{{.Id}}', args.image]).decode().strip()
    if image != args.image:
        raise client.Refusal('Existing image mismatch')
    identity = secrets.token_hex(16)
    name = prefix + identity
    database = db_prefix + identity[:12]
    volume = name + '-data'
    folder = root / '.local' / name
    folder.mkdir(parents=True, exist_ok=False)
    report = {'status': 'failed', 'fixtureId': identity, 'nativeAcceptance': 'pending'}
    owned = False
    password = secrets.token_hex(24)
    env = dict(runtime.env, POSTGRES_PASSWORD=password)
    try:
        runtime.run(['docker', 'volume', 'create', '--label', client.LABEL + '=' + identity, volume])
        runtime.run(['docker', 'create', '--name', name, '--label', client.LABEL + '=' + identity,
                     '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_USER=fixture',
                     '-e', 'POSTGRES_DB=' + database, '-p', '127.0.0.1::5432',
                     '--mount', 'type=volume,src=' + volume + ',dst=/var/lib/postgresql/data', args.image], env=env)
        owned = True
        client.assert_owned(runtime, name, identity)
        runtime.run(['docker', 'start', name])
        until = min(runtime.deadline, time.monotonic() + 30)
        while True:
            try:
                raw = runtime.run(['docker', 'exec', name, 'psql', '-U', 'fixture', '-d', database,
                                   '-Atqc', "SELECT current_database() || '|' || current_user"])
            except client.Refusal:
                if time.monotonic() >= until:
                    raise client.Refusal('Readiness deadline exceeded') from None
                time.sleep(0.2)
                continue
            if raw.decode().strip() != database + '|fixture':
                raise client.Refusal('Database identity mismatch')
            break
        client.assert_owned(runtime, name, identity)
        migrations = files[:2] + (('backend/migrations/004-asset-dates.sql',) if profile in ('dates', 'export-v2', 'warranty', 'warranty-overview') else ())
        if profile in ('location', 'location-overview', 'export-v3', 'sort', 'selection-export'):
            migrations += ('backend/migrations/004-asset-dates.sql', 'backend/migrations/005-asset-location.sql')
        if profile == 'import-v2':
            migrations += ('backend/migrations/003-asset-import.sql', 'backend/migrations/004-asset-dates.sql')
        if profile == 'import-v3':
            migrations += ('backend/migrations/003-asset-import.sql', 'backend/migrations/004-asset-dates.sql', 'backend/migrations/005-asset-location.sql')
        if profile in ('check', 'check-overview', 'selection-export-v2'):
            migrations += ('backend/migrations/003-asset-import.sql', 'backend/migrations/004-asset-dates.sql',
                           'backend/migrations/005-asset-location.sql', 'backend/migrations/006-asset-check.sql')
        for migration in migrations:
            runtime.run(['docker', 'exec', '-i', name, 'psql', '-v', 'ON_ERROR_STOP=1',
                         '-U', 'fixture', '-d', database], data=(root / migration).read_bytes())
        runtime.run(['docker', 'exec', '-i', name, 'psql', '-v', 'ON_ERROR_STOP=1', '-U', 'fixture', '-d', database],
                    data=("CREATE TABLE public." + marker_table + "(marker text NOT NULL);"
                          "INSERT INTO public." + marker_table + " VALUES ('" + identity + "');").encode())
        ports = json.loads(runtime.run(['docker', 'inspect', '--format', '{{json .NetworkSettings.Ports}}', name]))
        binding = ports.get('5432/tcp') if isinstance(ports, dict) else None
        if (not isinstance(binding, list) or len(binding) != 1 or binding[0].get('HostIp') != '127.0.0.1' or
                not str(binding[0].get('HostPort', '')).isdigit()):
            raise client.Refusal('Unexpected port binding')
        port = int(binding[0]['HostPort'])
        if not 1024 <= port <= 65535 or port in (5432, 5433):
            raise client.Refusal('Unexpected fixture port')
        test_env = dict(runtime.env)
        test_env.update({env_prefix + '_FIXTURE_OPT_IN': opt_in,
                         env_prefix + '_FIXTURE_MARKER': identity,
                         env_prefix + '_FIXTURE_URL': 'postgresql://fixture:%s@127.0.0.1:%s/%s' % (password, port, database)})
        result_file = folder / 'jest-result.json'
        runtime.run(['node', str(root / files[-1]), '--runInBand', '--runTestsByPath',
                     str(root / files[2]), '--json', '--outputFile=' + str(result_file)],
                    cwd=root / 'backend', env=test_env)
        if result_file.stat().st_size > 1024 * 1024:
            raise client.Refusal('Oversized test result')
        expected = 6 if profile == 'check' else 8 if profile in ('import-v2', 'import-v3', 'selection-export-v2') else 7 if profile in ('warranty-overview', 'selection-export') else 4
        validate_result(json.loads(result_file.read_text(encoding='utf-8')), expected)
        if verification is not None:
            verification(runtime, name, database, identity, folder)
            report['datesDatabaseRecovery'] = True
        report.update(status='completed', repositoryTests=expected, syntheticOnly=True)
    finally:
        runtime.deadline = time.monotonic() + 30
        cleanup = 'stopped'
        if owned:
            try:
                client.assert_owned(runtime, name, identity)
                runtime.run(['docker', 'stop', '--time', '10', name])
                running = runtime.run(['docker', 'inspect', '--format', '{{json .State.Running}}', name])
                if json.loads(running) is not False:
                    raise client.Refusal('Owned container still running')
            except (client.Refusal, OSError, ValueError):
                cleanup = 'incomplete'
                report['status'] = 'failed'
        report['cleanup'] = cleanup
        (folder / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        if cleanup != 'stopped':
            raise client.Refusal('Cleanup incomplete; retain resources')
    return report


def main():
    """Only an explicit invocation may create synthetic resources."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    parser.add_argument('--image', default='')
    args = parser.parse_args()
    try:
        execute(Path(__file__).resolve().parent.parent, args, client.Runtime(seconds=120))
    except (client.Refusal, OSError, ValueError):
        print('Category fixture failed/refused; no retry, inspect retained evidence.')
        return 1
    print('Category repository assertions completed; owned container stopped.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
