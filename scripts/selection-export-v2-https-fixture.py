"""Explicit synthetic selection export HTTPS acceptance using the existing owned TLS lifecycle."""
import argparse
import importlib.util
import json
import sys
from pathlib import Path
from selection_export_v2_https_contract import AcceptanceRefusal, validate_result as validate_selection_result

_spec = importlib.util.spec_from_file_location('selection_tls_lifecycle', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)
FILES = ('flutter/lib/api/asset_selection_export_v2.dart',
         'backend/dist/domains/assets/asset-selection-export-v2.module.js',
         'backend/dist/domains/assets/asset-selection-export-v2.controller.js',
         'backend/dist/domains/assets/asset-selection-export-v2.repository.js',
         'backend/dist/domains/assets/asset-selection-export-v2.config.js',
         'backend/dist/domains/assets/asset-selection-export-v2.js',
         'flutter/tool/selection_export_v2_https_acceptance.dart',
         'flutter/tool/export_https_acceptance.dart', 'flutter/tool/native_https_seed.dart',
         'flutter/tool/client_https_acceptance.dart', 'flutter/lib/api/asset_export_v3.dart',
         'flutter/lib/api/asset_api.dart', 'flutter/lib/api/asset_dates.dart',
         'flutter/lib/api/asset_selection_export.dart', 'scripts/selection_export_v2_https_contract.py',
         'scripts/selection-export-v2-https-fixture.py',
         'backend/src/domains/assets/asset-selection-export.controller.ts',
         'backend/src/domains/assets/asset-export-v3.controller.ts',
         'backend/dist/domains/assets/asset-export-v3.controller.js',
         'backend/dist/domains/assets/asset-export-v3.js',
         'backend/dist/domains/assets/asset-export-v3.module.js',
         'backend/dist/domains/assets/asset-export-v3.repository.js')


def preflight(root, args):
    """Missing selected source refuses before shared resource creation."""
    if any(not (root/name).is_file() for name in FILES):
        raise client.Refusal('Selection export fixture source missing')
    if not Path(sys.executable).is_absolute() or not Path(sys.executable).is_file():
        raise client.Refusal('Explicit Python executable missing')
    client.preflight(root, args)


def validate_result(value):
    """Partial, malformed or incorrectly typed output is not acceptance."""
    try:
        validate_selection_result(value)
    except AcceptanceRefusal as error:
        raise client.Refusal('Selection HTTPS Dart result incomplete') from error


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Run the fixed marker-bound real Dart client once, with default TLS checks."""
    output = runtime.run([args.dart, '--disable-dart-dev', str(root/'flutter/tool/selection_export_v2_https_acceptance.dart'),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity, sys.executable], cwd=root/'flutter')
    value = json.loads(output)
    stages = ('http-contract', 'marker', 'registration', 'empty', 'create',
              'date-location', 'anonymous', 'selection', 'read-only', 'sign-out')
    if isinstance(value, dict) and value.get('status') == 'failed' and value.get('stage') in stages:
        (folder/'selection-export-diagnostic.json').write_text(json.dumps({'status': 'failed', 'stage': value['stage']})+'\n', encoding='utf-8')
    validate_result(value)
    return dict(status='completed', syntheticOnly=True, selectionExportDartClient=True, nativeAcceptance='pending')


def main():
    """Require explicit synthetic arguments; never build, pull or retry implicitly."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--'+name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--'+name, type=int, default=0)
    args = parser.parse_args()
    args.selection_export_mode = True
    args.selection_export_v2_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(), acceptance)
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Selection export HTTPS fixture failed/refused; no automatic retry.')
        return 1
    print('Selection export Dart HTTPS acceptance completed; native remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
