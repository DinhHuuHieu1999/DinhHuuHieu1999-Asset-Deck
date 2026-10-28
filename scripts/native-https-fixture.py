"""Opt-in native session; never builds, retries, changes trust or launches on import."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import time
import uuid
from datetime import datetime, timezone

_spec = importlib.util.spec_from_file_location('client_fixture', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)


def verify_candidate(root, args):
    """Require a complete hashed deployment, pinned to the intended TLS endpoint."""
    v3 = client.import_v3_mode(args)
    export_v3 = client.export_v3_mode(args)
    location = client.location_mode(args)
    v2 = client.import_v2_mode(args)
    enabled = client.import_mode(args) or v2 or v3
    if not args.execute_native or not args.execute_synthetic:
        raise client.Refusal('Explicit native and synthetic opt-in required')
    if not 1 <= args.minutes <= 30:
        raise client.Refusal('Session must be between one and thirty minutes')
    executable = Path(args.candidate)
    if not executable.is_absolute() or executable.name != 'asset_desk.exe':
        raise client.Refusal('Explicit Asset Desk executable required')
    allowed = (root / '.local' / 'windows-candidates').resolve()
    try:
        executable.resolve().relative_to(allowed)
    except ValueError:
        raise client.Refusal('Candidate must be in the isolated candidate directory') from None
    folder = executable.parent
    for path in [folder] + list(folder.parents):
        if path.is_symlink() or (path.exists() and getattr(path.stat(), 'st_file_attributes', 0) & 1024):
            raise client.Refusal('Linked candidate directory refused')
    if not executable.is_file() or executable.is_symlink():
        raise client.Refusal('Candidate executable missing or linked')
    manifest = folder / 'candidate.json'
    if not manifest.is_file() or manifest.stat().st_size > 1024 * 1024:
        raise client.Refusal('Candidate manifest missing or oversized')
    value = json.loads(manifest.read_text(encoding='utf-8'))
    if (not isinstance(value, dict) or value.get('schemaVersion') != 1 or
            value.get('endpoint') != 'https://localhost:%s/api/v1' % args.tls_port or
            value.get('buildMode') != 'release' or not isinstance(value.get('files'), dict)):
        raise client.Refusal('Candidate endpoint or release manifest mismatch')
    defines = {'ASSET_DESK_ENABLE_IMPORT': 'true'}
    if v2:
        defines.update(ASSET_DESK_ENABLE_IMPORT_V2='true', ASSET_DESK_ENABLE_ASSET_DATES='true')
    if location:
        defines = {'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
                   'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
    if export_v3:
        defines = {'ASSET_DESK_ENABLE_EXPORT_V3': 'true',
                   'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
                   'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
    if v3:
        defines = {'ASSET_DESK_ENABLE_IMPORT': 'true',
                   'ASSET_DESK_ENABLE_IMPORT_V3': 'true',
                   'ASSET_DESK_ENABLE_ASSET_DATES': 'true',
                   'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true'}
    if (enabled or location or export_v3) and value.get('buildDefines') != defines:
        raise client.Refusal('Candidate feature build contract missing')
    files = value['files']
    if not {'asset_desk.exe', 'flutter_windows.dll', 'data/icudtl.dat'} <= set(files):
        raise client.Refusal('Required deployment files missing')
    actual = set()
    for path in folder.rglob('*'):
        if path.is_symlink() or getattr(path.stat(), 'st_file_attributes', 0) & 1024:
            raise client.Refusal('Linked deployment refused')
        if path.is_file() and path != manifest:
            actual.add(path.relative_to(folder).as_posix())
    if set(files) != actual:
        raise client.Refusal('Deployment inventory mismatch')
    for name, expected in files.items():
        # Compare the discovered relative inventory before joining untrusted names.
        if not isinstance(expected, str) or hashlib.sha256((folder / name).read_bytes()).hexdigest() != expected:
            raise client.Refusal('Deployment hash mismatch')
    return executable


def seed_source(args):
    """Select a fixed source path without accepting arbitrary seed programs."""
    return 'flutter/tool/native_export_v3_seed.dart' if client.export_v3_mode(args) else 'flutter/tool/native_https_seed.dart'


def preflight(root, args):
    """Validate all source/candidate prerequisites before creating resources."""
    verify_candidate(root, args)
    if os.name != 'nt':
        raise client.Refusal('Native session requires Windows')
    if not (root / seed_source(args)).is_file():
        raise client.Refusal('Native seed source missing')
    client.preflight(root, args)


def prepare_import_file(folder, v2=False, v3=False):
    """Create one inert synthetic snapshot; never consume operator inventory."""
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    record = {'id': str(uuid.uuid4()), 'name': 'Synthetic native imported asset',
              'category': 'fixture', 'serial': 'IMPORT-%_1', 'status': 'stored',
              'notes': 'Synthetic import only', 'version': 1,
              'createdAt': now, 'updatedAt': now}
    if type(v2) is not bool or type(v3) is not bool or (v2 and v3):
        raise client.Refusal('Invalid synthetic import version')
    if v2 or v3:
        record.update(purchasedOn='2024-02-29', warrantyExpiresOn='2027-02-28')
    if v3:
        record['location'] = 'Synthetic room %_1'
    payload = json.dumps({'exportedAt': now, 'complete': True, 'recordCount': 1,
                          'records': [record]}, ensure_ascii=False, separators=(',', ':'))
    envelope = {'format': 'asset-desk-inventory', 'schemaVersion': 3 if v3 else 2 if v2 else 1, 'payload': payload,
                'sha256': hashlib.sha256(payload.encode('utf-8')).hexdigest()}
    destination = folder / ('inventory-import-v3-synthetic.json' if v3 else 'inventory-import-v2-synthetic.json' if v2 else 'inventory-import-synthetic.json')
    with destination.open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(envelope, ensure_ascii=False, separators=(',', ':'))+'\n')
    return destination


def native_session(root, args, runtime, folder, identity, backend, proxy):
    """Seed through default TLS, then hold exact owned children for a bounded session."""
    executable = verify_candidate(root, args)
    endpoint = 'https://localhost:%s/api/v1' % args.tls_port
    raw = runtime.run([args.dart, '--disable-dart-dev', str(root / seed_source(args)),
                       '--synthetic-only', endpoint, identity], cwd=root / 'flutter')
    seed = json.loads(raw)
    if (not isinstance(seed, dict) or set(seed) != {'username', 'password', 'assetName'} or
            not all(isinstance(v, str) and 0 < len(v) <= 120 for v in seed.values()) or
            not seed['username'].startswith('n') or seed['assetName'] != 'Synthetic native asset'):
        raise client.Refusal('Native seed result incomplete')
    handoff = dict(seed, endpoint=endpoint, fixtureId=identity, syntheticOnly=True,
                   expiresAtEpoch=int(time.time() + args.minutes * 60),
                   instructions='Sign in, search, create/edit/refresh. Do not use a real account or equipment data.')
    if client.import_mode(args) or client.import_v2_mode(args) or client.import_v3_mode(args):
        import_file = prepare_import_file(folder, v2=client.import_v2_mode(args), v3=client.import_v3_mode(args))
        handoff.update(importFile=str(import_file), expectedBefore=1, expectedAfter=2,
                       importedAssetName='Synthetic native imported asset',
                       instructions='Sign in, open Import, choose the synthetic file, review and explicitly confirm once; refresh. Never use real data.')
    if client.import_v3_mode(args):
        handoff.update(importSchemaVersion=3, purchasedOn='2024-02-29',
                       warrantyExpiresOn='2027-02-28', locationLabel='Synthetic room %_1',
                       instructions='Sign in; choose Import inventory JSON v3 and the synthetic file. Review dates/location, save private recovery to a new file, acknowledge and confirm once. Refresh: two assets. Restore the same recovery file and explicitly replay: still two. Never use real data.')
    if client.location_mode(args):
        handoff.update(locationMode=True, expectedAssets=1,
                       locationLabel='Synthetic room %_1',
                       instructions='Sign in; edit the synthetic asset location to Synthetic room %_1; save and refresh. Test exact and unknown filters, clear the location and refresh. Verify base fields remain unchanged. Never use real data.')
    if client.export_v3_mode(args):
        handoff.update(exportV3Mode=True, expectedAssets=1,
                       purchasedOn='2024-02-29', warrantyExpiresOn='2027-02-28',
                       locationLabel='Synthetic room %_1',
                       instructions='Sign in; export JSON v3, Prepare and Save to a new private file. Inspect that file: checksum, one asset, both dates and location must match. Cancel file selection must retain preview. Invalid JSON must clear preview. No import or real data.')
    # Credentials are private local fixture evidence, never stdout or tracked source.
    with (folder / 'operator-handoff.json').open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(handoff, indent=2) + '\n')
    app = runtime.start([str(executable)], executable.parent)
    until = min(runtime.deadline, time.monotonic() + args.minutes * 60)
    reason = 'deadline'
    while time.monotonic() < until:
        if backend.poll() is not None or proxy.poll() is not None:
            raise client.Refusal('Owned fixture service exited during native session')
        if app.poll() is not None:
            if app.returncode != 0:
                raise client.Refusal('Native candidate exited unsuccessfully')
            reason = 'app-closed'
            break
        time.sleep(min(1, max(0, until - time.monotonic())))
    return {'status': 'session-ended', 'syntheticOnly': True, 'nativeAcceptance': 'pending',
            'sessionEnd': reason, 'candidateSha256': hashlib.sha256(executable.read_bytes()).hexdigest(),
            'candidateManifestSha256': hashlib.sha256((executable.parent / 'candidate.json').read_bytes()).hexdigest(),
            'seedSourceSha256': hashlib.sha256((root / seed_source(args)).read_bytes()).hexdigest()}


def main():
    """Only explicit CLI opt-in may start the fixture or native executable."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-native', action='store_true')
    parser.add_argument('--execute-synthetic', action='store_true')
    parser.add_argument('--export-v3-mode', action='store_true')
    parser.add_argument('--location-mode', action='store_true')
    parser.add_argument('--import-mode', action='store_true')
    parser.add_argument('--import-v2-mode', action='store_true')
    parser.add_argument('--import-v3-mode', action='store_true')
    parser.add_argument('--candidate', default='')
    parser.add_argument('--minutes', type=int, default=30)
    for name in ('image', 'cert', 'key'):
        parser.add_argument('--' + name, default='')
    parser.add_argument('--dart', default='dart.exe')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, default=0)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(seconds=args.minutes * 60 + 300), native_session)
    except (client.Refusal, OSError, ValueError):
        print('Native fixture failed or refused. No automatic retry; inspect retained fixture.')
        return 1
    print('Native session ended and owned resources stopped. Manual acceptance remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
