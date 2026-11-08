"""Explicit synthetic date-aware export HTTPS acceptance using the existing owned TLS lifecycle."""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location('export_v3_tls_lifecycle', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)
FILES = ('flutter/tool/export_v3_https_acceptance.dart',
         'flutter/tool/export_https_acceptance.dart', 'flutter/tool/native_https_seed.dart',
         'flutter/tool/client_https_acceptance.dart', 'flutter/lib/api/asset_export_v3.dart',
         'flutter/lib/api/asset_api.dart', 'flutter/lib/api/asset_dates.dart',
         'backend/src/domains/assets/asset-export-v3.controller.ts',
         'backend/dist/domains/assets/asset-export-v3.controller.js',
         'backend/dist/domains/assets/asset-export-v3.js',
         'backend/dist/domains/assets/asset-export-v3.module.js',
         'backend/dist/domains/assets/asset-export-v3.repository.js')


def preflight(root, args):
    """Missing selected source refuses before shared resource creation."""
    if any(not (root/name).is_file() for name in FILES):
        raise client.Refusal('Export v3 fixture source missing')
    if not Path(sys.executable).is_absolute() or not Path(sys.executable).is_file():
        raise client.Refusal('Explicit Python executable missing')
    client.preflight(root, args)


def validate_result(value):
    """Partial, malformed or incorrectly typed output is not acceptance."""
    expected = dict(status='completed', syntheticOnly=True, exportV3Acceptance=True, owners=2, assetCount=51,
                    digest='python-sha256-stdin', nativeDialog='not-exercised')
    if (not isinstance(value, dict) or value != expected or
            any(type(value.get(key)) is not type(item) for key, item in expected.items())):
        raise client.Refusal('Export v3 Dart result incomplete')


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Run the fixed marker-bound real Dart client once, with default TLS checks."""
    output = runtime.run([args.dart, '--disable-dart-dev', str(root/FILES[0]),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity, sys.executable], cwd=root/'flutter')
    value = json.loads(output)
    stages = ('http-contract', 'marker', 'registration', 'empty', 'create', 'date-update', 'location-update', 'anonymous', 'export-v3',
              'owner-isolation', 'v1-preservation', 'filter-independence', 'read-only', 'sign-out')
    if isinstance(value, dict) and value.get('status') == 'failed' and value.get('stage') in stages:
        (folder/'export-v3-diagnostic.json').write_text(json.dumps({'status': 'failed', 'stage': value['stage']})+'\n', encoding='utf-8')
    validate_result(value)
    return dict(status='completed', syntheticOnly=True, exportV3DartClient=True, nativeAcceptance='pending')


def main():
    """Require explicit synthetic arguments; never build, pull or retry implicitly."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--'+name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--'+name, type=int, default=0)
    args = parser.parse_args()
    args.export_v3_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(), acceptance)
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Export v3 HTTPS fixture failed/refused; no automatic retry.')
        return 1
    print('Export v3 Dart HTTPS acceptance completed; native remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
