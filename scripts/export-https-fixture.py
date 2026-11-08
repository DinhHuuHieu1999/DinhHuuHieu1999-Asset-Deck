"""Opt-in synthetic export acceptance using the existing owned HTTPS lifecycle."""
import argparse
import hashlib
import http.cookiejar
import importlib.util
import json
from pathlib import Path
import re
import secrets
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

_spec = importlib.util.spec_from_file_location('client_fixture', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check(value):
    if not value:
        raise client.Refusal('Synthetic export assertion failed')


def run_dart_export(root, args, runtime, identity):
    """Run the marker-guarded client once and reject any partial result."""
    output = runtime.run([args.dart, '--disable-dart-dev',
                          str(root / 'flutter/tool/export_https_acceptance.dart'),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port,
                          identity, sys.executable], cwd=root / 'flutter')
    result = json.loads(output)
    check(result == {'status': 'completed', 'syntheticOnly': True, 'owners': 2,
                     'assetCount': 51, 'digest': 'python-sha256-stdin',
                     'nativeDialog': 'not-exercised'})
    # Equality alone would accept Python bool/int equivalence.
    check(type(result['owners']) is int and type(result['assetCount']) is int
          and result['syntheticOnly'] is True)


def export_preflight(root, args):
    """Refuse missing client source before the lifecycle creates resources."""
    client.preflight(root, args)
    if getattr(args, 'dart_export_client', False):
        for name in ('flutter/tool/export_https_acceptance.dart',
                     'flutter/tool/native_https_seed.dart',
                     'flutter/lib/api/asset_export.dart',
                     'flutter/lib/api/strict_export_json.dart'):
            check((root / name).is_file())
        check(Path(sys.executable).is_absolute() and Path(sys.executable).is_file())


def decode_export(value, expected):
    """Independently verify exact payload bytes and complete bounded fields."""
    check(set(value) == {'format', 'schemaVersion', 'payload', 'sha256'})
    check(value['format'] == 'asset-desk-inventory' and type(value['schemaVersion']) is int and value['schemaVersion'] == 1)
    check(isinstance(value['payload'], str))
    check(hashlib.sha256(value['payload'].encode('utf-8')).hexdigest() == value['sha256'])
    payload = json.loads(value['payload'])
    check(payload['complete'] is True and type(payload['recordCount']) is int)
    check(payload['recordCount'] == expected == len(payload['records']))
    fields = {'id', 'name', 'category', 'serial', 'status', 'notes', 'version', 'createdAt', 'updatedAt'}
    check(all(set(row) == fields for row in payload['records']))
    return payload


def concurrent_snapshot(runtime, folder, name, identity, sql, fetch):
    """Require an observed uncommitted writer across the complete HTTP read."""
    label = 'asset-export-concurrency-' + identity
    writer = runtime.start(['docker', 'exec', name, 'psql', '-v', 'ON_ERROR_STOP=1',
        '-U', 'fixture', '-d', 'fixture', '-c',
        "BEGIN; UPDATE assets.assets SET name='Synthetic concurrent after'; "
        "SELECT pg_sleep(10) /* "+label+" */; COMMIT;"], folder)
    def writer_sleeping():
        return sql("SELECT count(*) FROM pg_stat_activity WHERE wait_event='PgSleep' "
                   "AND query LIKE '%"+label+"%';") == '1'
    until = min(runtime.deadline, time.monotonic()+5)
    while not writer_sleeping():
        check(writer.poll() is None and time.monotonic() < until)
        time.sleep(0.1)
    during = fetch()
    check(writer_sleeping())
    check(all(row['name'].startswith('Synthetic export ') for row in during['records']))
    try:
        check(writer.wait(timeout=min(15, runtime.remaining())) == 0)
    except subprocess.TimeoutExpired:
        raise client.Refusal('Synthetic writer timed out') from None
    after = fetch()
    check(all(row['name'] == 'Synthetic concurrent after' for row in after['records']))


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    base = 'https://localhost:%s' % args.tls_port
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    token = None
    csrf = None

    def checkpoint(stage, **details):
        # Fixed stage labels and numeric statuses only; never body/token/URL data.
        (folder / 'export-checkpoint.json').write_text(
            json.dumps(dict(stage=stage, **details), indent=2)+'\n', encoding='utf-8')

    def request(path, data=None, expected=200):
        headers = {'Accept': 'application/json', 'x-request-timestamp': str(int(time.time()*1000))}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        raw = None
        if data is not None:
            headers.update({'Content-Type': 'application/json', 'x-csrf-token': csrf})
            raw = json.dumps(data).encode('utf-8')
        label = ('marker' if path.startswith('/__asset_desk_fixture/') else
                 'csrf' if path.endswith('/csrf-token') else
                 'register' if path.endswith('/register') else 'export')
        checkpoint(label, expectedStatus=expected)
        req = urllib.request.Request(base + path, data=raw, headers=headers)
        try:
            response = opener.open(req, timeout=min(15, runtime.remaining()))
        except urllib.error.HTTPError as error:
            response = error
        except urllib.error.URLError as error:
            reason = error.reason
            checkpoint(label, transportError=type(reason).__name__,
                       certificateVerification=isinstance(reason, ssl.SSLCertVerificationError))
            raise client.Refusal('Synthetic HTTPS transport failed') from None
        with response:
            checkpoint(label, expectedStatus=expected, observedStatus=response.status)
            check(response.status == expected)
            body = response.read(1024*1024+1)
            check(len(body) <= 1024*1024)
            if expected == 200 and path.startswith('/api/v1/assets/export'):
                check(response.headers.get('Cache-Control') == 'no-store')
            return json.loads(body)

    marker = request('/__asset_desk_fixture/' + identity)
    check(marker == {'fixtureId': identity, 'syntheticOnly': True})
    request('/api/v1/assets/export', expected=401)
    csrf = request('/api/v1/csrf-token')['token']
    owners = []
    for prefix in ('a', 'b'):
        suffix = secrets.token_hex(10)
        result = request('/api/v1/auth/register', {
            'email': prefix+suffix+'@example.invalid', 'username': prefix+suffix,
            'name': 'Synthetic export owner', 'password': 'Synthetic-'+suffix+'-42!'}, expected=201)
        owner = result['user']['id']
        check(re.fullmatch('[a-f0-9]{24}', owner) is not None)
        owners.append((owner, result['accessToken']))
    token = owners[0][1]
    decode_export(request('/api/v1/assets/export'), 0)
    name = 'asset-client-' + identity
    client.assert_owned(runtime, name, identity)

    def sql(statement):
        return runtime.run(['docker', 'exec', '-i', name, 'psql', '-v', 'ON_ERROR_STOP=1',
                            '-U', 'fixture', '-d', 'fixture', '-Atq'], data=statement.encode('utf-8')).decode().strip()

    def seed(count):
        sql("DELETE FROM assets.assets; INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes) "
            "SELECT md5(i::text)::uuid,'%s','Synthetic export '||i,'fixture','serial','stored','Unicode \u00e9\u4e2d' "
            "FROM generate_series(1,%s) i;" % (owners[0][0], count))

    def digest():
        return sql("SELECT md5(coalesce(string_agg(row_to_json(a)::text,'' ORDER BY id),'')) FROM assets.assets a;")

    for count in (51, 500):
        checkpoint('seed', recordCount=count)
        seed(count)
        before = digest()
        payload = decode_export(request('/api/v1/assets/export'), count)
        check([(r['updatedAt'], r['id']) for r in payload['records']] ==
              sorted([(r['updatedAt'], r['id']) for r in payload['records']], reverse=True))
        decode_export(request('/api/v1/assets/export?q=missing&status=retired&owner='+owners[1][0]), count)
        check(digest() == before)
        token = owners[1][1]
        decode_export(request('/api/v1/assets/export'), 0)
        token = owners[0][1]
    seed(501)
    before = digest()
    request('/api/v1/assets/export', expected=422)
    check(digest() == before)
    seed(500)
    sql("UPDATE assets.assets SET notes=repeat(chr(34),2000);")
    before = digest()
    request('/api/v1/assets/export', expected=422)
    check(digest() == before)
    if getattr(args, 'concurrent_snapshot', False):
        seed(51)
        checkpoint('concurrent-update')
        concurrent_snapshot(runtime, folder, name, identity, sql,
                            lambda: decode_export(request('/api/v1/assets/export'), 51))
    if getattr(args, 'dart_export_client', False):
        checkpoint('dart-export-client')
        run_dart_export(root, args, runtime, identity)
    checkpoint('completed')
    return {'status': 'completed', 'syntheticOnly': True, 'exportAcceptance': {
        'empty': True, 'records51and500': True, 'twoOwners': True, 'anonymous401': True,
        'checksumPython': True, 'readOnlyHashes': True, 'overflow501andBytes422': True,
        'ordering': True, 'concurrentSnapshot': bool(getattr(args, 'concurrent_snapshot', False)), 'dartExportClient': bool(getattr(args, 'dart_export_client', False))}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    parser.add_argument('--concurrent-snapshot', action='store_true')
    parser.add_argument('--dart-export-client', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--'+name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--'+name, type=int, default=0)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        export_preflight(root, args)
        report = client.execute(root, args, client.Runtime(), acceptance=acceptance)
        print(json.dumps({'status': report['status'], 'fixtureId': report['fixtureId'], 'cleanup': report['cleanup']}))
        return 0
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Export fixture failed or refused; no automatic retry. Inspect retained evidence.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
