"""Opt-in native session; never builds, retries, changes trust or launches on import."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import time

_spec = importlib.util.spec_from_file_location('client_fixture', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)


def verify_candidate(root, args):
    """Require a complete hashed deployment, pinned to the intended TLS endpoint."""
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


def preflight(root, args):
    """Validate all source/candidate prerequisites before creating resources."""
    verify_candidate(root, args)
    if os.name != 'nt':
        raise client.Refusal('Native session requires Windows')
    if not (root / 'flutter/tool/native_https_seed.dart').is_file():
        raise client.Refusal('Native seed source missing')
    client.preflight(root, args)


def native_session(root, args, runtime, folder, identity, backend, proxy):
    """Seed through default TLS, then hold exact owned children for a bounded session."""
    executable = verify_candidate(root, args)
    endpoint = 'https://localhost:%s/api/v1' % args.tls_port
    raw = runtime.run([args.dart, '--disable-dart-dev', str(root / 'flutter/tool/native_https_seed.dart'),
                       '--synthetic-only', endpoint, identity], cwd=root / 'flutter')
    seed = json.loads(raw)
    if (not isinstance(seed, dict) or set(seed) != {'username', 'password', 'assetName'} or
            not all(isinstance(v, str) and 0 < len(v) <= 120 for v in seed.values()) or
            not seed['username'].startswith('n') or seed['assetName'] != 'Synthetic native asset'):
        raise client.Refusal('Native seed result incomplete')
    handoff = dict(seed, endpoint=endpoint, fixtureId=identity, syntheticOnly=True,
                   expiresAtEpoch=int(time.time() + args.minutes * 60),
                   instructions='Sign in, search, create/edit/refresh. Do not use a real account or equipment data.')
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
            'seedSourceSha256': hashlib.sha256((root / 'flutter/tool/native_https_seed.dart').read_bytes()).hexdigest()}


def main():
    """Only explicit CLI opt-in may start the fixture or native executable."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-native', action='store_true')
    parser.add_argument('--execute-synthetic', action='store_true')
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
