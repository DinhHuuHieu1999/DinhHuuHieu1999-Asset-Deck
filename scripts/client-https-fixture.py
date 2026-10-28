"""Opt-in synthetic HTTPS acceptance. Importing this module has no side effects."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import time

LABEL = 'asset-desk.client-https'
FILES = ('backend/dist/main.js', 'backend/migrations/001-auth-accounts.sql',
         'backend/migrations/002-assets.sql', 'scripts/client-https-proxy.mjs',
         'scripts/import-recovery-fault.mjs', 'scripts/client-https-proxy-cli.mjs', 'flutter/tool/client_https_acceptance.dart',
         'flutter/.dart_tool/package_config.json', 'flutter/lib/api/asset_api.dart',
         'flutter/lib/api/asset.dart', 'flutter/lib/api/asset_session.dart',
         'flutter/lib/api/asset_store.dart', 'scripts/client-https-backend.cjs')


IMPORT_FILES = ('backend/migrations/003-asset-import.sql',
                'flutter/tool/import_https_acceptance.dart',
                'flutter/lib/api/asset_import.dart')

class Refusal(Exception):
    """Safe refusal without including subprocess output or credentials."""


def import_mode(args):
    """Accept only an explicit boolean profile, never arbitrary env/SQL input."""
    value = getattr(args, 'import_mode', False)
    if type(value) is not bool:
        raise Refusal('Invalid import fixture profile')
    return value


DATES_FILES = ('backend/migrations/004-asset-dates.sql',
               'backend/dist/domains/assets/asset-dates.module.js',
               'flutter/tool/dates_https_acceptance.dart', 'flutter/lib/api/asset_dates.dart')


def dates_mode(args):
    """Dates is a fixed opt-in capability, never an inherited operator setting."""
    value = getattr(args, 'dates_mode', False)
    if type(value) is not bool or (value and import_mode(args)):
        raise Refusal('Invalid dates fixture profile')
    return value


IMPORT_V2_FILES = IMPORT_FILES + DATES_FILES + (
    'backend/dist/domains/assets/asset-import-v2.config.js',
    'backend/dist/domains/assets/asset-import-v2.module.js',
    'backend/dist/domains/assets/asset-import-v2.controller.js',
    'backend/dist/domains/assets/asset-import-v2.repository.js',
    'backend/dist/domains/assets/asset-import-v2.js',
    'backend/dist/domains/assets/asset-import-v2-parser.js',
    'flutter/tool/import_v2_https_acceptance.dart',
    'flutter/lib/api/asset_import_v2.dart',
    'flutter/lib/api/asset_import_v2_recovery.dart',
    'flutter/lib/api/asset_export_v2.dart',
)


def import_v2_mode(args):
    """Separate fixed profile; never widen legacy import/dates fixtures."""
    value = getattr(args, 'import_v2_mode', False)
    if type(value) is not bool or (value and (import_mode(args) or dates_mode(args))):
        raise Refusal('Invalid import v2 fixture profile')
    return value



LOCATION_FILES = DATES_FILES + (
    'backend/migrations/005-asset-location.sql',
    'backend/src/domains/assets/asset-location.ts',
    'backend/src/domains/assets/asset-location.config.ts',
    'backend/src/domains/assets/asset-location.module.ts',
    'backend/src/domains/assets/asset-location.controller.ts',
    'backend/src/domains/assets/asset-location.repository.ts',
    'backend/dist/domains/assets/asset-location.js',
    'backend/dist/domains/assets/asset-location.config.js',
    'backend/dist/domains/assets/asset-location.module.js',
    'backend/dist/domains/assets/asset-location.controller.js',
    'backend/dist/domains/assets/asset-location.repository.js',
    'flutter/tool/location_https_acceptance.dart',
    'flutter/lib/api/asset_location.dart',
)


def location_mode(args):
    """Location is a fixed opt-in profile, incompatible with other profile flags."""
    value = getattr(args, 'location_mode', False)
    if type(value) is not bool or (value and (import_mode(args) or dates_mode(args) or import_v2_mode(args))):
        raise Refusal('Invalid location fixture profile')
    return value


EXPORT_V3_FILES = LOCATION_FILES + tuple(
    'backend/dist/domains/assets/asset-export-v3' + suffix + '.js'
    for suffix in ('', '.config', '.module', '.controller', '.repository')
) + ('flutter/lib/api/asset_export_v3.dart', 'flutter/tool/export_v3_https_acceptance.dart')


def export_v3_mode(args):
    """Export v3 has its own exclusive, explicitly typed fixture profile."""
    value = getattr(args, 'export_v3_mode', False)
    if type(value) is not bool or (value and (import_mode(args) or dates_mode(args) or import_v2_mode(args) or location_mode(args))):
        raise Refusal('Invalid export v3 fixture profile')
    return value


IMPORT_V3_FILES = IMPORT_FILES + EXPORT_V3_FILES + tuple(
    'backend/dist/domains/assets/asset-import-v3' + suffix + '.js'
    for suffix in ('', '.config', '.module', '.controller', '.repository', '-parser')
) + ('backend/dist/domains/assets/asset-import-v2-parser.js',
     'flutter/tool/import_v3_https_acceptance.dart',
     'flutter/lib/api/asset_import_v3.dart')


def import_v3_mode(args):
    """Only a dedicated exclusive boolean profile enables import v3."""
    value = getattr(args, 'import_v3_mode', False)
    if type(value) is not bool or (value and any(getattr(args, key, False) is not False
            for key in ('import_mode', 'dates_mode', 'import_v2_mode',
                        'location_mode', 'export_v3_mode'))):
        raise Refusal('Invalid import v3 fixture profile')
    return value


def fixture_files(args):
    """Return a fixed source/artifact set for the selected fixture profile."""
    if import_v3_mode(args):
        return FILES + IMPORT_V3_FILES
    if export_v3_mode(args):
        return FILES + EXPORT_V3_FILES
    if location_mode(args):
        return FILES + LOCATION_FILES
    if import_v2_mode(args):
        return FILES + IMPORT_V2_FILES
    dates = dates_mode(args)
    return FILES + (DATES_FILES if dates else IMPORT_FILES if import_mode(args) else ())


def preflight(root, args):
    """Check explicit opt-in and all local prerequisites before creating resources."""
    if not args.execute_synthetic or not args.image.startswith('sha256:') or len(args.image) != 71:
        raise Refusal('Explicit opt-in and an existing immutable image ID are required')
    if any(c not in '0123456789abcdef' for c in args.image[7:]):
        raise Refusal('Invalid image ID')
    for name in fixture_files(args):
        if not (root / name).is_file():
            raise Refusal('Required source or artifact is missing')
    for value in (args.cert, args.key):
        if not value or not Path(value).is_absolute() or not Path(value).is_file():
            raise Refusal('Explicit existing absolute TLS paths are required')
    for command in ('docker', 'node', args.dart):
        if not shutil.which(command):
            raise Refusal('Required executable is missing')
    dart = shutil.which(args.dart)
    if os.name == 'nt' and Path(dart).suffix.lower() != '.exe':
        raise Refusal('Use the SDK dart.exe directly, not a batch wrapper')
    ports = (args.db_port, args.backend_port, args.tls_port)
    if len(set(ports)) != 3 or any(p < 1024 or p > 65535 or p in (8180, 8443, 28443) for p in ports):
        raise Refusal('Three distinct non-default loopback ports are required')
    # Binding is read-only availability probing; actual listeners still fail closed on races.
    for port in ports:
        with socket.socket() as probe:
            try:
                probe.bind(('127.0.0.1', port))
            except OSError:
                raise Refusal('A fixture port is occupied') from None


class Runtime:
    """Bounded subprocess adapter; private output is never included in errors."""
    def __init__(self, seconds=300):
        self.deadline = time.monotonic() + seconds
        self.children = []
        self.env = {key: value for key, value in os.environ.items()
                    if key.upper() in ('PATH', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT', 'TEMP', 'TMP', 'HOME', 'USERPROFILE', 'LOCALAPPDATA')}

    def remaining(self):
        value = self.deadline - time.monotonic()
        if value <= 0:
            raise Refusal('Fixture deadline exceeded')
        return value

    def run(self, command, data=None, env=None, cwd=None):
        try:
            result = subprocess.run(command, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=env or self.env, cwd=cwd, timeout=min(120, self.remaining()), check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise Refusal('Fixture command failed or timed out') from None
        if result.returncode:
            raise Refusal('Fixture command failed')
        return result.stdout

    def start(self, command, cwd, env=None):
        self.remaining()
        try:
            child = subprocess.Popen(command, cwd=cwd, env=env or self.env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            raise Refusal('Fixture child failed to start') from None
        self.children.append(child)
        return child

    def wait_port(self, port, child):
        until = min(self.deadline, time.monotonic() + 30)
        while time.monotonic() < until:
            if child.poll() is not None:
                raise Refusal('Fixture child exited before readiness')
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                    return
            except OSError:
                time.sleep(0.1)
        raise Refusal('Fixture listener readiness timed out')

    def wait_backend(self, folder, identity, port, child):
        until = min(self.deadline, time.monotonic() + 30)
        while time.monotonic() < until:
            if child.poll() is not None:
                raise Refusal('Owned backend exited before readiness')
            marker = folder / 'backend-ready.json'
            if marker.is_file():
                try:
                    raw = marker.read_bytes()
                    if len(raw) > 1024:
                        raise Refusal('Invalid backend readiness marker')
                    value = json.loads(raw)
                except (OSError, ValueError):
                    raise Refusal('Invalid backend readiness marker') from None
                if value != {'fixtureId': identity, 'port': port, 'pid': child.pid}:
                    raise Refusal('Backend listener ownership mismatch')
                return
            time.sleep(0.1)
        raise Refusal('Owned backend readiness timed out')

    def stop_children(self):
        # Exact handles only; never process-name discovery or taskkill /T.
        failed = False
        for child in reversed(self.children):
            try:
                if child.poll() is None:
                    child.terminate()
                    try:
                        child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait(timeout=10)
            except (OSError, subprocess.TimeoutExpired):
                failed = True
        if failed:
            raise Refusal('An owned child did not stop')


def assert_owned(runtime, name, identity):
    """Refuse cleanup unless Docker's current label matches this exact fixture."""
    raw = runtime.run(['docker', 'inspect', '--format', '{{json .Config.Labels}}', name])
    labels = json.loads(raw)
    if not isinstance(labels, dict) or labels.get(LABEL) != identity:
        raise Refusal('Container ownership mismatch; resource retained')


PROGRESS_STAGES = ('database-create', 'database-readiness', 'migrations',
                   'backend-readiness', 'proxy-readiness', 'dart-client',
                   'native-session', 'completed')


def record_progress(folder, identity, stage):
    """Flush fixed, credential-free milestones; never serialize commands/errors."""
    if (stage not in PROGRESS_STAGES or not isinstance(identity, str) or
            len(identity) != 32 or any(c not in '0123456789abcdef' for c in identity)):
        raise Refusal('Invalid progress milestone')
    mode = 'x' if stage == 'database-create' else 'a'
    with (folder / 'progress.jsonl').open(mode, encoding='utf-8') as stream:
        stream.write(json.dumps({'fixtureId': identity, 'stage': stage}) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def execute(root, args, runtime, acceptance=None):
    """Run once, retain evidence/volume, and stop only resources created here."""
    v3 = import_v3_mode(args)
    export_v3 = export_v3_mode(args) or v3
    location = location_mode(args) or export_v3
    v2 = import_v2_mode(args)
    enabled = import_mode(args) or v2 or v3
    dates = dates_mode(args) or v2 or location
    if (enabled or dates) and acceptance is None:
        raise Refusal('Import fixture requires its dedicated acceptance driver')
    if enabled and any(not (root / name).is_file() for name in IMPORT_FILES):
        raise Refusal('Import fixture source is missing')
    if v2 and any(not (root / name).is_file() for name in IMPORT_V2_FILES):
        raise Refusal('Import v2 fixture source is missing')
    if v3 and any(not (root / name).is_file() for name in IMPORT_V3_FILES):
        raise Refusal('Import v3 fixture source is missing')
    disabled_v3 = getattr(args, 'disabled_v3_route', False)
    if type(disabled_v3) is not bool or (disabled_v3 and not v3):
        raise Refusal('Invalid disabled v3 route profile')
    disabled_v2 = getattr(args, 'disabled_v2_route', False)
    if type(disabled_v2) is not bool or (disabled_v2 and not v2):
        raise Refusal('Invalid disabled v2 route profile')
    image = runtime.run(['docker', 'image', 'inspect', '--format', '{{.Id}}', args.image]).decode().strip()
    if image != args.image:
        raise Refusal('Existing image identity mismatch')
    identity = secrets.token_hex(16)
    name = 'asset-client-' + identity
    volume = name + '-data'
    folder = root / '.local' / name
    folder.mkdir(parents=True, exist_ok=False)
    # An isolated cwd prevents the backend env loader from reading app-local env files.
    owned = False
    report = {'status': 'failed', 'fixtureId': identity, 'nativeAcceptance': 'pending', 'stage': 'database-create'}
    try:
        record_progress(folder, identity, 'database-create')
        runtime.run(['docker', 'volume', 'create', '--label', LABEL + '=' + identity, volume])
        password = secrets.token_hex(24)
        child_env = dict(runtime.env, POSTGRES_PASSWORD=password, PGPASSWORD=password)
        runtime.run(['docker', 'create', '--name', name, '--label', LABEL + '=' + identity,
                     '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_USER=fixture', '-e', 'POSTGRES_DB=fixture',
                     '-p', '127.0.0.1:%s:5432' % args.db_port, '--mount', 'type=volume,src=' + volume + ',dst=/var/lib/postgresql/data', args.image], env=child_env)
        owned = True
        assert_owned(runtime, name, identity)
        runtime.run(['docker', 'start', name])
        report['stage'] = 'database-readiness'
        record_progress(folder, identity, 'database-readiness')
        # Readiness polling, not a retry of the acceptance scenario.
        ready = False
        until = min(runtime.deadline, time.monotonic() + 30)
        while time.monotonic() < until:
            try:
                identity_result = runtime.run(['docker', 'exec', '-e', 'PGPASSWORD', name, 'psql',
                                               '-h', '127.0.0.1', '-U', 'fixture', '-d', 'fixture',
                                               '-Atqc', "SELECT current_database() || '|' || current_user"], env=child_env)
                if identity_result.decode().strip() != 'fixture|fixture':
                    raise Refusal('Database identity mismatch')
                ready = True
                break
            except Refusal:
                time.sleep(0.2)
        if not ready:
            raise Refusal('Database readiness timed out')
        report['stage'] = 'migrations'
        record_progress(folder, identity, 'migrations')
        migrations = FILES[1:3] + (IMPORT_FILES[:1] if enabled else DATES_FILES[:1] if dates else ())
        if v2:
            migrations = FILES[1:3] + IMPORT_FILES[:1] + DATES_FILES[:1]
        if location:
            migrations = FILES[1:3] + DATES_FILES[:1] + ('backend/migrations/005-asset-location.sql',)
        if v3:
            migrations = FILES[1:3] + IMPORT_FILES[:1] + DATES_FILES[:1] + ('backend/migrations/005-asset-location.sql',)
        for migration in migrations:
            runtime.run(['docker', 'exec', '-i', name, 'psql', '-v', 'ON_ERROR_STOP=1', '-U', 'fixture', '-d', 'fixture'], data=(root / migration).read_bytes())
        env = dict(runtime.env, NODE_ENV='production', BACKEND_HTTP_PORT=str(args.backend_port),
                   AUTH_POSTGRES_URL='postgresql://fixture:%s@127.0.0.1:%s/fixture' % (password, args.db_port),
                   JWT_ACCESS_SECRET=secrets.token_hex(32), CSRF_SECRET=secrets.token_hex(32),
                   CSRF_ENABLED='true', CSRF_COOKIE_SECURE='true', AUTH_EXPOSE_RESET_TOKEN='false',
                   REQUEST_FRESHNESS_ENABLED='true', THROTTLE_LIMIT='1000', ASSET_DESK_FIXTURE_ID=identity)
        env['ASSET_IMPORT_V3_ENABLED'] = 'true' if v3 and not disabled_v3 else 'false'
        env['ASSET_IMPORT_ENABLED'] = 'true' if enabled else 'false'
        env['ASSET_DATES_ENABLED'] = 'true' if dates else 'false'
        env['ASSET_EXPORT_V3_ENABLED'] = 'true' if export_v3 else 'false'
        env['ASSET_LOCATION_ENABLED'] = 'true' if location else 'false'
        env['ASSET_IMPORT_V2_ENABLED'] = 'true' if v2 and not disabled_v2 else 'false'
        report['stage'] = 'backend-readiness'
        record_progress(folder, identity, 'backend-readiness')
        backend = runtime.start(['node', '--require', str(root / 'scripts/client-https-backend.cjs'), str(root / FILES[0])], folder, env)
        runtime.wait_backend(folder, identity, args.backend_port, backend)
        report['stage'] = 'proxy-readiness'
        record_progress(folder, identity, 'proxy-readiness')
        proxy = runtime.start(['node', str(root / 'scripts/client-https-proxy-cli.mjs'), '--synthetic-only',
                               str(args.backend_port), str(args.tls_port), identity, args.cert, args.key] + (['--import-v3-enabled'] if v3 else ['--export-v3-enabled'] if export_v3 else ['--location-enabled'] if location else ['--import-v2-enabled'] if v2 else ['--import-enabled'] if enabled else ['--dates-enabled'] if dates else []), folder)
        runtime.wait_port(args.tls_port, proxy)
        if acceptance is None:
            report['stage'] = 'dart-client'
            record_progress(folder, identity, 'dart-client')
            output = runtime.run([args.dart, '--disable-dart-dev', str(root / 'flutter/tool/client_https_acceptance.dart'),
                                  '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity], cwd=root / 'flutter')
            result = json.loads(output)
            if result != {'status': 'completed', 'syntheticOnly': True, 'assetCount': 51, 'owners': 2}:
                raise Refusal('Client result is incomplete')
            report.update(result)
        else:
            report['stage'] = 'native-session'
            record_progress(folder, identity, 'native-session')
            report.update(acceptance(root, args, runtime, folder, identity, backend, proxy))
        report['stage'] = 'completed'
        record_progress(folder, identity, 'completed')
        report['sourceHashes'] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in fixture_files(args)}
    finally:
        cleanup_failed = False
        try:
            runtime.stop_children()
        except (Refusal, OSError):
            cleanup_failed = True
        # Cleanup has its own bounded budget even when the scenario deadline expired.
        runtime.deadline = time.monotonic() + 30
        if owned:
            try:
                assert_owned(runtime, name, identity)
                runtime.run(['docker', 'stop', '--time', '10', name])
            except (Refusal, OSError, ValueError):
                cleanup_failed = True
        for port in (args.db_port, args.backend_port, args.tls_port):
            try:
                with socket.socket() as probe:
                    probe.settimeout(1)
                    if probe.connect_ex(('127.0.0.1', port)) == 0:
                        cleanup_failed = True
            except OSError:
                cleanup_failed = True
        report['cleanup'] = 'incomplete' if cleanup_failed else 'stopped'
        if cleanup_failed:
            report['status'] = 'failed'
        (folder / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
        if cleanup_failed:
            raise Refusal('Cleanup incomplete; inspect retained fixture')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    parser.add_argument('--image', default='')
    parser.add_argument('--cert', default='')
    parser.add_argument('--key', default='')
    parser.add_argument('--dart', default='dart.exe' if os.name == 'nt' else 'dart')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, default=0)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        execute(root, args, Runtime())
    except (Refusal, OSError, ValueError):
        print('Fixture failed or refused; inspect retained resources. No automatic retry.')
        return 1
    print('Synthetic client HTTPS acceptance completed; native acceptance remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
