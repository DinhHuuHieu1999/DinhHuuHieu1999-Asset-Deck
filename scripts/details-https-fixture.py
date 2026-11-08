"""Opt-in details HTTP/Dart acceptance; importing never starts a fixture."""
import hashlib
import importlib.util
import json
from pathlib import Path

_spec = importlib.util.spec_from_file_location('details_shared_tls', Path(__file__).with_name('serial-https-fixture.py'))
shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(shared)
client = shared.client
FILES = ('flutter/tool/details_https_acceptance.dart', 'flutter/lib/api/asset_read.dart') + shared.FILES[1:]


def validate_dart_result(value):
    """Reject partial, malformed and legacy serial results."""
    expected = {'status': 'completed', 'syntheticOnly': True, 'detailsAcceptance': True,
                'owners': 2, 'readOnlySnapshots': 2}
    if (not isinstance(value, dict) or value != expected or
            value.get('syntheticOnly') is not True or value.get('detailsAcceptance') is not True or
            type(value.get('owners')) is not int or type(value.get('readOnlySnapshots')) is not int):
        raise client.Refusal('Details Dart result incomplete')


def source_hashes(root):
    """Hash the fixed details artifacts even when invoked outside the CLI."""
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in FILES}


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Run exactly one real-client driver under the owned lifecycle deadline."""
    before = source_hashes(root)
    output = runtime.run([args.dart, '--disable-dart-dev', str(root / FILES[0]),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity], cwd=root / 'flutter')
    validate_dart_result(json.loads(output))
    if source_hashes(root) != before:
        raise client.Refusal('Details source changed')
    return {'status': 'completed', 'syntheticOnly': True, 'detailsDartClient': True, 'nativeAcceptance': 'pending'}


def main():
    """Use the shared explicit CLI, preflight and ownership-checked shutdown."""
    original_files, original_acceptance = shared.FILES, shared.acceptance
    try:
        shared.FILES = FILES
        shared.acceptance = acceptance
        return shared.main()
    finally:
        shared.FILES, shared.acceptance = original_files, original_acceptance


if __name__ == '__main__':
    raise SystemExit(main())
