"""Explicit synthetic check-date HTTPS acceptance using the existing owned TLS lifecycle."""
import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

_spec = importlib.util.spec_from_file_location('check_tls_lifecycle', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)
FILES = ('flutter/tool/check_https_acceptance.dart',) + tuple(
    name for name in client.CHECK_FILES if name != 'flutter/tool/check_https_acceptance.dart')


def preflight(root, args):
    """Missing selected source refuses before shared resource creation."""
    if any(not (root/name).is_file() for name in FILES):
        raise client.Refusal('Check-date fixture source missing')
    if not Path(sys.executable).is_absolute() or not Path(sys.executable).is_file():
        raise client.Refusal('Explicit Python executable missing')
    client.preflight(root, args)


def validate_result(value):
    """Partial, malformed or incorrectly typed output is not acceptance."""
    expected = dict(status='completed', syntheticOnly=True, checkDateAcceptance=True, checkedBeforeAcceptance=True, owners=2, nativeDialog='not-exercised')
    if (not isinstance(value, dict) or value != expected or
            any(type(value.get(key)) is not type(item) for key, item in expected.items())):
        raise client.Refusal('Check-date Dart result incomplete')


def source_hashes(root):
    """Hash only fixed public source/artifacts; never env, TLS or credentials."""
    return {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in FILES}


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Run the fixed marker-bound real Dart client once, with default TLS checks."""
    before = source_hashes(root)
    output = runtime.run([args.dart, '--disable-dart-dev', str(root/FILES[0]),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity], cwd=root/'flutter')
    value = json.loads(output)
    stages = ('arguments', 'marker', 'anonymous-csrf', 'registration', 'create', 'update', 'owner-version', 'details', 'checked-before', 'filter-clear', 'sign-out')
    stages += tuple('checked-before-%s-%s' % (scope, boundary) for scope in ('base', 'warranty', 'location', 'combined') for boundary in ('boundary', 'earlier'))
    if isinstance(value, dict) and value.get('status') == 'failed' and value.get('stage') in stages:
        diagnostic = {'status': 'failed', 'stage': value['stage']}
        if value.get('failureKind') in ('api', 'format', 'assertion'):
            diagnostic['failureKind'] = value['failureKind']
        if type(value.get('httpStatus')) is int and 100 <= value['httpStatus'] <= 599:
            diagnostic['httpStatus'] = value['httpStatus']
        (folder/'check-diagnostic.json').write_text(json.dumps(diagnostic)+'\n', encoding='utf-8')
    validate_result(value)
    if source_hashes(root) != before:
        raise client.Refusal('Check-date source changed during acceptance')
    return dict(status='completed', syntheticOnly=True, checkDateDartClient=True, checkedBeforeDartClient=True,
                nativeAcceptance='pending', checkSourceHashes=before)


def main():
    """Require explicit synthetic arguments; never build, pull or retry implicitly."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--'+name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--'+name, type=int, default=0)
    args = parser.parse_args()
    args.check_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(), acceptance)
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Check-date HTTPS fixture failed/refused; no automatic retry.')
        return 1
    print('Check-date Dart HTTPS acceptance completed; native remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
