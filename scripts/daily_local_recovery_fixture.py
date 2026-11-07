"""Opt-in base recovery fixture entrypoint; importing starts no services."""

import argparse
import importlib.util
import json
from pathlib import Path
import secrets
import shutil
import sys
import time

from daily_local_adapter import assert_ports_free
from daily_local_fixture import preflight as runtime_preflight
from daily_local_fixture_database import SyntheticDatabase
from daily_local_recovery_acceptance import accept_recovery
from daily_local_recovery_sessions import RecoverySessions


def preflight(root, args):
    """Validate source artifacts and four distinct ports before any write."""
    runtime_preflight(root, args)
    port = args.restore_port
    if (type(port) is not int or not 1024 <= port <= 65535
            or port in (8180, 8443, 28443, args.db_port, args.backend_port, args.tls_port)):
        raise ValueError('Distinct non-reserved restore port required')
    if not shutil.which('node'):
        raise ValueError('Node executable unavailable')


def execute(root, args, runtime, database_factory=SyntheticDatabase,
            sessions_factory=RecoverySessions, accept=accept_recovery,
            ports_free=assert_ports_free):
    """Create two fresh synthetic databases and retain artifacts after cleanup."""
    preflight(root, args)
    ports = (args.db_port, args.restore_port, args.backend_port, args.tls_port)
    ports_free(ports)
    identity = secrets.token_hex(16)
    folder = root / '.local' / ('daily-recovery-' + identity)
    folder.mkdir(parents=True, exist_ok=False)
    databases, sessions = [], None
    report = {'status': 'failed', 'cleanup': 'pending', 'fixtureId': identity,
              'stage': 'configuration', 'profile': 'base-001-002-only',
              'nativeAcceptance': 'not-tested-inert-substitute'}
    try:
        candidate = Path(args.candidate).resolve()
        python = str(Path(sys.executable).resolve())
        config = dict(node=str(Path(shutil.which('node')).resolve()), python=python,app=python,
            backend_supervisor=str(root/'scripts/daily-local-backend.cjs'),
            backend_entry=str(candidate/'dist/main.js'),backend_cwd=str(candidate),
            gateway_entry=str(root/'scripts/daily_local_gateway_child.py'),
            tls_cert=str(Path(args.cert).resolve()),tls_key=str(Path(args.key).resolve()),
            state_dir=str(folder),backend_port=args.backend_port,https_port=args.tls_port)
        sessions = sessions_factory(config, runtime)
        databases = [database_factory(runtime,args.image,port,secrets.token_hex(16))
                     for port in (args.db_port,args.restore_port)]
        report['stage'] = 'recovery-acceptance'
        # Wrapper keeps a separate cleanup deadline without changing acceptance.
        accept(databases[0],databases[1],root,folder,sessions,runtime.remaining,cleanup_databases=False)
        report['status'], report['stage'] = 'completed', 'completed'
    finally:
        runtime.deadline = time.monotonic() + 45
        clean = True
        if sessions is not None:
            try: sessions.close_all()
            except Exception: clean = False
        # Do not stop DBs while an owned app/backend may still be active.
        if clean:
            for database in reversed(databases):
                try: database.stop()
                except Exception: clean = False
        try: ports_free(ports)
        except Exception: clean = False
        report['cleanup'] = 'stopped' if clean else 'incomplete'
        if not clean: report['status'] = 'failed'
        with (folder/'result.json').open('x',encoding='utf-8') as stream:
            json.dump(report,stream,indent=2)
            stream.write('\n')
    if report['status'] != 'completed':
        raise RuntimeError('Recovery fixture incomplete; inspect retained evidence')
    return report


def main(argv=None):
    """Require explicit synthetic approval; never build, pull, retry or deploy."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic',action='store_true')
    for name in ('candidate','image','cert','key'):
        parser.add_argument('--'+name,required=True)
    for name in ('db-port','restore-port','backend-port','tls-port'):
        parser.add_argument('--'+name,type=int,required=True)
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    try:
        preflight(root,args)
        spec = importlib.util.spec_from_file_location('daily_recovery_commands',root/'scripts/client-https-fixture.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        print(json.dumps(execute(root,args,module.Runtime(seconds=120))))
        return 0
    except Exception:
        print('Daily recovery fixture failed; inspect retained redacted evidence',file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
