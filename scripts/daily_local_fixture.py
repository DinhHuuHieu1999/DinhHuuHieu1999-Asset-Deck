"""Opt-in daily runtime fixture; no build, Docker call, or service starts on import."""

import argparse
import importlib.util
import json
from pathlib import Path
import re
import secrets
import shutil
import sys
import time

from daily_local_acceptance import accept_session
from daily_local_adapter import DailyAdapter, assert_ports_free
from daily_local_config import validate_config
from daily_local_environment import backend_environment
from daily_local_fixture_client import SyntheticClient
from daily_local_fixture_database import SyntheticDatabase, MIGRATIONS
from daily_local_lifecycle import Launcher
from daily_local_session import SessionLock


def preflight(root, args):
    """Refuse missing opt-in, candidate escapes and reserved ports before writes."""
    if getattr(args, 'execute_synthetic', False) is not True:
        raise ValueError('Explicit synthetic execution approval is required')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', args.image):
        raise ValueError('Existing immutable image is required')
    ports = (args.db_port, args.backend_port, args.tls_port)
    if (len(set(ports)) != 3 or any(type(p) is not int or not 1024 <= p <= 65535 for p in ports)
            or any(p in (8180, 8443, 28443) for p in ports)):
        raise ValueError('Distinct non-reserved loopback ports are required')
    candidate = Path(args.candidate)
    if not candidate.is_absolute():
        raise ValueError('Absolute backend candidate directory is required')
    candidate.resolve().relative_to((root / 'backend/.local/daily-candidates').resolve())
    required = [candidate / 'dist/main.js', root / 'scripts/daily-local-backend.cjs',
                root / 'scripts/daily_local_gateway_child.py']
    required += [root / 'backend/migrations' / name for name in MIGRATIONS]
    required += [Path(args.cert), Path(args.key)]
    for path in required:
        if not path.is_absolute() or not path.is_file():
            raise ValueError('Required fixture artifact is missing')
        for parent in (path,) + tuple(path.parents):
            if parent.is_symlink() or (parent.exists() and
                    getattr(parent.stat(), 'st_file_attributes', 0) & 1024):
                raise ValueError('Linked fixture paths are refused')
    if any((candidate / 'env' / name).exists() for name in ('.env', '.env.production')):
        raise ValueError('Candidate environment fallback is refused')


def execute(root, args, runtime, database_factory=SyntheticDatabase,
            launcher_factory=Launcher, adapter_factory=DailyAdapter,
            client_factory=SyntheticClient, lock_factory=SessionLock,
            ports_free=assert_ports_free):
    """Run one isolated acceptance, retain evidence and stop verified resources."""
    preflight(root, args)
    ports_free((args.db_port, args.backend_port, args.tls_port))
    identity = secrets.token_hex(16)
    folder = root / '.local' / ('daily-runtime-' + identity)
    folder.mkdir(parents=True, exist_ok=False)
    database = database_factory(runtime, args.image, args.db_port, identity)
    launcher = None
    report = {'status': 'failed', 'fixtureId': identity, 'cleanup': 'pending',
              'nativeAcceptance': 'not-tested-inert-substitute', 'events': []}
    try:
        report['stage'] = 'database-create'
        database.create()
        report['stage'] = 'database-ready'
        database.wait_ready()
        report['stage'] = 'database-migrate'
        database.migrate(root)
        report['stage'] = 'runtime-config'
        private = dict(AUTH_POSTGRES_URL='postgresql://fixture:{}@127.0.0.1:{}/fixture'.format(
                           database.password, args.db_port),
                       JWT_ACCESS_SECRET=secrets.token_hex(32), CSRF_SECRET=secrets.token_hex(32))
        environment = backend_environment(private, runtime.env)
        candidate = Path(args.candidate).resolve()
        python = Path(sys.executable).resolve()
        node = shutil.which('node')
        if not node:
            raise RuntimeError('Node executable is unavailable')
        config = validate_config(dict(
            node=str(Path(node).resolve()), python=str(python), app=str(python),
            backend_supervisor=str(root / 'scripts/daily-local-backend.cjs'),
            backend_entry=str(candidate / 'dist/main.js'), backend_cwd=str(candidate),
            gateway_entry=str(root / 'scripts/daily_local_gateway_child.py'),
            tls_cert=str(Path(args.cert).resolve()), tls_key=str(Path(args.key).resolve()),
            state_dir=str(folder), backend_port=args.backend_port, https_port=args.tls_port))
        adapter = adapter_factory(config, environment)
        launcher = launcher_factory(adapter)
        def close_substitute():
            item = adapter.processes.children.get('app')
            if item is not None:
                # Inert Python stdin substitute only, never a Flutter application.
                child = item[1]
                if child.poll() is None:
                    child.stdin.close()
                    child.wait(timeout=5)
        report['stage'] = 'runtime-acceptance'
        result = accept_session(launcher, lock_factory(folder),
            client_factory(args.tls_port, runtime.remaining), close_substitute,
            runtime.remaining, report['events'].append)
        report.update(result)
        report['stage'] = 'completed'
    finally:
        cleanup_ok = launcher is None or not launcher.owned
        runtime.deadline = time.monotonic() + 30
        try:
            database.stop()
        except Exception:
            cleanup_ok = False
        try:
            ports_free((args.db_port, args.backend_port, args.tls_port))
        except Exception:
            cleanup_ok = False
        report['cleanup'] = 'stopped' if cleanup_ok else 'incomplete'
        if not cleanup_ok:
            report['status'] = 'failed'
        with (folder / 'result.json').open('x', encoding='utf-8') as stream:
            json.dump(report, stream, indent=2)
            stream.write('\n')
    if report['status'] != 'completed':
        raise RuntimeError('Daily fixture incomplete; retained evidence requires review')
    return report


def main(argv=None):
    """Reuse the existing bounded command runtime, not its legacy proxy lifecycle."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('candidate', 'image', 'cert', 'key'):
        parser.add_argument('--' + name, required=True)
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, required=True)
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    try:
        preflight(root, args)
        spec = importlib.util.spec_from_file_location('daily_fixture_commands',
                    root / 'scripts/client-https-fixture.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = execute(root, args, module.Runtime(seconds=120))
        print(json.dumps(result))
        return 0
    except Exception:
        print('Daily runtime fixture failed; inspect retained redacted evidence', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
