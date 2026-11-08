"""Opt-in saved filters backend restart acceptance; no regular target or retry."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

_spec = importlib.util.spec_from_file_location('saved_filters_restart_base', Path(__file__).with_name('saved-filters-https-fixture.py'))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
client = base.client
FILES = ('flutter/tool/saved_filters_restart_https_acceptance.dart',
         'flutter/tool/import_recovery_https_acceptance.dart')


def preflight(root, args):
    """Refuse missing fixed stage sources before shared lifecycle side effects."""
    if any(not (root / name).is_file() for name in FILES):
        raise client.Refusal('Saved filters restart source missing')
    base.preflight(root, args)


def stage(root, args, runtime, folder, identity, name):
    """Run a new real Dart client process at each fixed stage without retry."""
    if name not in ('prepare', 'verify'):
        raise client.Refusal('Unknown saved filters restart stage')
    output = runtime.run([args.dart, '--disable-dart-dev', str(root / FILES[0]),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port,
                          identity, name, str(folder)], cwd=root / 'flutter')
    value = json.loads(output)
    expected = {'status': 'completed', 'stage': name, 'syntheticOnly': True, 'owners': 2}
    if value != expected or any(type(value[k]) is not type(v) for k, v in expected.items()):
        raise client.Refusal('Saved filters restart stage incomplete')


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Persist, restart the exact backend, then compare definitions and assets."""
    hashes = {n: hashlib.sha256((root/n).read_bytes()).hexdigest() for n in FILES}
    stage(root, args, runtime, folder, identity, 'prepare')
    client.assert_owned(runtime, 'asset-client-' + identity, identity)
    runtime.restart_backend(folder, identity, args.backend_port, backend)
    stage(root, args, runtime, folder, identity, 'verify')
    if hashes != {n: hashlib.sha256((root/n).read_bytes()).hexdigest() for n in FILES}:
        raise client.Refusal('Restart acceptance source changed')
    return {'status': 'completed', 'syntheticOnly': True, 'savedFiltersBackendRestart': True,
            'freshDartClient': True, 'unchangedDefinitionsAndAssets': True}


def main():
    """Create one isolated opted-in TLS fixture; shared lifecycle retains resources."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--' + name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, default=0)
    args = parser.parse_args()
    args.check_mode = True
    args.saved_filters_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(seconds=180), acceptance)
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Saved filters restart fixture failed/refused; no retry.')
        return 1
    print('Saved filters backend restart completed; owned resources stopped.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
