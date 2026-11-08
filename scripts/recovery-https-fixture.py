"""Opt-in recovery acceptance, reusing the isolated import fixture lifecycle."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys
import subprocess
import hashlib
import urllib.request

_spec = importlib.util.spec_from_file_location('recovery_import_fixture', Path(__file__).with_name('import-https-fixture.py'))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
client = base.client
FILES = ('scripts/import-recovery-proxy-main.mjs', 'scripts/import-recovery-proxy-cli.mjs',
    'scripts/import-recovery-fault.mjs', 'flutter/tool/import_recovery_https_acceptance.dart',
    'flutter/lib/api/asset_import_recovery.dart', 'flutter/lib/api/asset_import_operation.dart')
EXPECTED = {'prepare': {'stage': 'prepare', 'saved': True},
    'submit': {'stage': 'submit', 'uncertain': True},
    'replay': {'stage': 'replay', 'sameIds': True, 'unchangedFields': True, 'count': 1}}


def preflight(root, args):
    """Require every fixed artifact before lifecycle side effects."""
    for name in FILES:
        if not (root / name).is_file():
            raise client.Refusal('Recovery source prerequisite missing')
    base.preflight(root, args)


def stage(root, args, runtime, folder, identity, name):
    """Each bounded invocation creates a fresh Dart process; never retries."""
    if name not in EXPECTED:
        raise client.Refusal('Unknown recovery stage')
    output = runtime.run([args.dart, '--disable-dart-dev',
        str(root / 'flutter/tool/import_recovery_https_acceptance.dart'), '--synthetic-only',
        'https://localhost:%s/api/v1' % args.tls_port, identity, sys.executable, name, str(folder)], cwd=root / 'flutter')
    value = json.loads(output)
    if value != EXPECTED[name] or any(type(value[k]) is not type(v) for k, v in EXPECTED[name].items()):
        raise client.Refusal('Recovery stage result incomplete')
    return value


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Prepare, lose acknowledgement once, then replay from a fresh process."""
    stage(root, args, runtime, folder, identity, 'prepare')
    control = folder / 'recovery-control.json'
    if control.is_symlink() or control.stat().st_size > 8192:
        raise client.Refusal('Invalid private fixture control')
    data = json.loads(control.read_text(encoding='utf-8'))
    key = data.get('requestId')
    if data.get('fixtureId') != identity or data.get('endpoint') != 'https://localhost:%s/api/v1' % args.tls_port or not isinstance(key, str) or not re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}', key):
        raise client.Refusal('Recovery control ownership mismatch')
    saved = folder / 'private-import-recovery.json'
    if saved.is_symlink() or saved.stat().st_size > 2 * 1024 * 1024:
        raise client.Refusal('Invalid recovery envelope file')
    envelope = json.loads(saved.read_text(encoding='utf-8'))
    payload = envelope.get('payload')
    if not isinstance(payload, str) or hashlib.sha256(payload.encode('utf-8')).hexdigest() != envelope.get('sha256'):
        raise client.Refusal('Independent recovery checksum mismatch')
    # Only the exact proxy child supplied by this lifecycle is replaced.
    if proxy.poll() is not None:
        raise client.Refusal('Owned proxy stopped before fault activation')
    proxy.terminate()
    try:
        proxy.wait(timeout=min(10, runtime.remaining()))
    except subprocess.TimeoutExpired:
        raise client.Refusal('Owned proxy did not stop within deadline') from None
    fault_proxy = runtime.start(['node', str(root / 'scripts/import-recovery-proxy-main.mjs'),
        '--synthetic-only', str(args.backend_port), str(args.tls_port), identity, args.cert, args.key,
        '--import-enabled', '--lose-import-ack', key], folder)
    runtime.wait_port(args.tls_port, fault_proxy)
    stage(root, args, runtime, folder, identity, 'submit')
    opener = urllib.request.build_opener(base.NoRedirect())
    with opener.open('https://localhost:%s/__asset_desk_fixture/%s' % (args.tls_port, identity), timeout=min(10, runtime.remaining())) as response:
        marker = json.loads(response.read(8193))
    if marker != {'fixtureId': identity, 'syntheticOnly': True, 'recoveryFault': {'claimed': True, 'suppressed': True}}:
        raise client.Refusal('Lost acknowledgement fault was not confirmed')
    name = 'asset-client-' + identity
    client.assert_owned(runtime, name, identity)
    query = ['docker', 'exec', name, 'psql', '-U', 'fixture', '-d', 'fixture', '-Atqc']
    counts = runtime.run(query + ['SELECT (SELECT count(*) FROM assets.assets), (SELECT count(*) FROM assets.import_receipts)'])
    if counts.decode().strip() != '2|1':
        raise client.Refusal('Expected committed import and receipt missing')
    sql = "SELECT json_build_object('assets',(SELECT json_agg(a ORDER BY id) FROM assets.assets a),'receipts',(SELECT json_agg(r ORDER BY request_id) FROM assets.import_receipts r))::text"
    before = runtime.run(query + [sql])
    stage(root, args, runtime, folder, identity, 'replay')
    if runtime.run(query + [sql]) != before:
        raise client.Refusal('Recovery replay changed committed rows')
    return {'status': 'completed', 'syntheticOnly': True, 'processReconstruction': True,
        'lostAcknowledgement': True, 'unchangedRows': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--' + name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, default=0)
    args = parser.parse_args()
    args.import_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(), acceptance)
        print('Synthetic recovery completed; native dialogs remain pending.')
        return 0
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Recovery fixture refused or failed; no automatic retry.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
