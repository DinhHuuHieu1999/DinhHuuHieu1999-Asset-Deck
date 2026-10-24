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
         'scripts/client-https-proxy-cli.mjs', 'flutter/tool/client_https_acceptance.dart',
         'flutter/.dart_tool/package_config.json', 'flutter/lib/api/asset_api.dart',
         'flutter/lib/api/asset.dart', 'flutter/lib/api/asset_session.dart',
         'flutter/lib/api/asset_store.dart', 'scripts/client-https-backend.cjs')


class Refusal(Exception):
    """Safe refusal without including subprocess output or credentials."""


def preflight(root, args):
    """Check explicit opt-in and all local prerequisites before creating resources."""
    if not args.execute_synthetic or not args.image.startswith('sha256:') or len(args.image) != 71:
        raise Refusal('Explicit opt-in and an existing immutable image ID are required')
    if any(c not in '0123456789abcdef' for c in args.image[7:]):
        raise Refusal('Invalid image ID')
    for name in FILES:
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


def execute(root, args, runtime):
    """Run once, retain evidence/volume, and stop only resources created here."""
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
        for migration in FILES[1:3]:
            runtime.run(['docker', 'exec', '-i', name, 'psql', '-v', 'ON_ERROR_STOP=1', '-U', 'fixture', '-d', 'fixture'], data=(root / migration).read_bytes())
        env = dict(runtime.env, NODE_ENV='production', BACKEND_HTTP_PORT=str(args.backend_port),
                   AUTH_POSTGRES_URL='postgresql://fixture:%s@127.0.0.1:%s/fixture' % (password, args.db_port),
                   JWT_ACCESS_SECRET=secrets.token_hex(32), CSRF_SECRET=secrets.token_hex(32),
                   CSRF_ENABLED='true', CSRF_COOKIE_SECURE='true', AUTH_EXPOSE_RESET_TOKEN='false',
                   REQUEST_FRESHNESS_ENABLED='true', THROTTLE_LIMIT='1000', ASSET_DESK_FIXTURE_ID=identity)
        report['stage'] = 'backend-readiness'
        backend = runtime.start(['node', '--require', str(root / 'scripts/client-https-backend.cjs'), str(root / FILES[0])], folder, env)
        runtime.wait_backend(folder, identity, args.backend_port, backend)
        report['stage'] = 'proxy-readiness'
        proxy = runtime.start(['node', str(root / 'scripts/client-https-proxy-cli.mjs'), '--synthetic-only',
                               str(args.backend_port), str(args.tls_port), identity, args.cert, args.key], folder)
        runtime.wait_port(args.tls_port, proxy)
        report['stage'] = 'dart-client'
        output = runtime.run([args.dart, '--disable-dart-dev', str(root / 'flutter/tool/client_https_acceptance.dart'),
                              '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity], cwd=root / 'flutter')
        result = json.loads(output)
        if result != {'status': 'completed', 'syntheticOnly': True, 'assetCount': 51, 'owners': 2}:
            raise Refusal('Client result is incomplete')
        report.update(result)
        report['stage'] = 'completed'
        report['sourceHashes'] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in FILES}
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
