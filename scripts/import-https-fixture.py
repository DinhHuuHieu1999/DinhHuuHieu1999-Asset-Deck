"""Opt-in isolated import HTTPS fixture; no work occurs on module import."""
import argparse
import importlib.util
import json
import http.cookiejar
import urllib.request
import urllib.error
import secrets
import time
import ssl
from pathlib import Path
import sys

_spec = importlib.util.spec_from_file_location('import_client_lifecycle',
    Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)

DRIVER_FILES = ('flutter/tool/export_https_acceptance.dart',
                'flutter/tool/native_https_seed.dart',
                'flutter/lib/api/asset_export.dart',
                'flutter/lib/api/strict_export_json.dart')
EXPECTED = {'status': 'completed', 'syntheticOnly': True, 'owners': 2,
            'imported': 2, 'exactReplay': True, 'conflict': True, 'accountBound': True,
            'sessionInvalidation': True}


def preflight(root, args):
    """Refuse absent source/profile before lifecycle creates any resource."""
    if not client.import_mode(args):
        raise client.Refusal('Explicit import profile required')
    for name in DRIVER_FILES:
        if not (root / name).is_file():
            raise client.Refusal('Import driver prerequisite missing')
    if not Path(sys.executable).is_absolute() or not Path(sys.executable).is_file():
        raise client.Refusal('Explicit digest executable required')
    client.preflight(root, args)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def rejection_cases(request, counts):
    """Run fixed negative cases and prove neither assets nor receipts changed."""
    before = counts()
    row = {'name': 'Synthetic refusal', 'category': 'fixture', 'serial': '',
           'status': 'stored', 'notes': 'Synthetic only'}
    batch = {'requestId': '12345678-1234-4234-8234-123456789abc', 'records': [row]}
    request(batch, expected=401, authenticated=False)
    request(batch, expected=403, csrf=False)
    request(dict(batch, records=[]), expected=400)
    request(dict(batch, owner='a'*24), expected=400)
    request(b'{', expected=400)
    # Proxy rejects the over-limit body before forwarding to the backend.
    request(b' '*(1024*1024+1), expected=413)
    if counts() != before:
        raise client.Refusal('Rejected import modified synthetic data')
    return {'anonymous401': True, 'csrf403': True, 'invalid400': True,
            'proxyOversize413': True, 'unchangedCounts': True}


def negative_acceptance(args, runtime, identity, checkpoint=lambda **details: None):
    """Default TLS, exact marker, synthetic credentials only; never log bodies."""
    base = 'https://localhost:%s' % args.tls_port
    opener = urllib.request.build_opener(NoRedirect(),
        urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    token = None
    csrf_token = None
    sequence = 0
    def request(path, data=None, expected=200, authenticated=True, csrf=True):
        nonlocal sequence
        sequence += 1
        checkpoint(stage='negative-http', requestIndex=sequence, expectedStatus=expected)
        headers = {'Accept': 'application/json',
                   'x-request-timestamp': str(int(time.time()*1000))}
        if token and authenticated:
            headers['Authorization'] = 'Bearer ' + token
        if data is not None:
            headers['Content-Type'] = 'application/json'
            if csrf and csrf_token:
                headers['x-csrf-token'] = csrf_token
        raw = data if isinstance(data, bytes) else (json.dumps(data).encode() if data is not None else None)
        req = urllib.request.Request(base+path, data=raw, headers=headers)
        try:
            response = opener.open(req, timeout=min(15, runtime.remaining()))
        except urllib.error.HTTPError as error:
            response = error
        except urllib.error.URLError as error:
            checkpoint(stage='negative-transport', requestIndex=sequence,
                       certificateVerification=isinstance(error.reason, ssl.SSLCertVerificationError))
            raise client.Refusal('Synthetic import HTTPS transport failed') from None
        with response:
            checkpoint(stage='negative-response', requestIndex=sequence,
                       expectedStatus=expected, observedStatus=response.status)
            body = response.read(1024*1024+1)
            if response.status != expected or len(body) > 1024*1024:
                raise client.Refusal('Synthetic import HTTP assertion failed')
            return json.loads(body)
    if request('/__asset_desk_fixture/'+identity) != {'fixtureId': identity, 'syntheticOnly': True}:
        raise client.Refusal('Synthetic HTTPS marker mismatch')
    csrf_token = request('/api/v1/csrf-token')['token']
    suffix = secrets.token_hex(12)
    account = request('/api/v1/auth/register', {'email': suffix+'@example.invalid',
        'username': 'n'+suffix, 'name': 'Synthetic negative import',
        'password': 'Synthetic-'+suffix+'-42!'}, expected=201)
    token = account['accessToken']
    name = 'asset-client-'+identity
    client.assert_owned(runtime, name, identity)
    def counts():
        return runtime.run(['docker', 'exec', name, 'psql', '-U', 'fixture', '-d', 'fixture',
            '-Atqc', 'SELECT (SELECT count(*) FROM assets.assets), (SELECT count(*) FROM assets.import_receipts)'])
    return rejection_cases(lambda data, **kwargs: request('/api/v1/assets/import', data, **kwargs), counts)


CHECKPOINT_STAGES = frozenset(('negative-start', 'negative-http',
    'negative-response', 'negative-transport', 'dart-driver-start',
    'dart-driver-returned', 'completed'))


def write_checkpoint(folder, details):
    """Persist fixed labels/statuses only; never include request or error text."""
    if details.get('stage') not in CHECKPOINT_STAGES or set(details) - {
        'stage', 'requestIndex', 'expectedStatus', 'observedStatus', 'certificateVerification'}:
        raise client.Refusal('Unsafe fixture checkpoint')
    for key, value in details.items():
        if key in ('requestIndex', 'expectedStatus', 'observedStatus'):
            if type(value) is not int or not 1 <= value <= 599:
                raise client.Refusal('Invalid fixture checkpoint status')
        if key == 'certificateVerification' and type(value) is not bool:
            raise client.Refusal('Invalid fixture checkpoint flag')
    (folder / 'import-checkpoint.json').write_text(json.dumps(details, indent=2)+'\n', encoding='utf-8')


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Invoke the real Dart client once; reject missing or partial evidence."""
    def checkpoint(**details):
        write_checkpoint(folder, details)
    checkpoint(stage='negative-start')
    negative = negative_acceptance(args, runtime, identity, checkpoint)
    checkpoint(stage='dart-driver-start')
    output = runtime.run([args.dart, '--disable-dart-dev',
        str(root / 'flutter/tool/import_https_acceptance.dart'), '--synthetic-only',
        'https://localhost:%s/api/v1' % args.tls_port, identity, sys.executable],
        cwd=root / 'flutter')
    checkpoint(stage='dart-driver-returned')
    result = json.loads(output)
    if result != EXPECTED or any(type(result[k]) is not type(v) for k, v in EXPECTED.items()):
        raise client.Refusal('Import client result incomplete')
    checkpoint(stage='completed')
    return dict(EXPECTED, rejectionAcceptance=negative)


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
        report = client.execute(root, args, client.Runtime(), acceptance)
        print(json.dumps({'status': report['status'], 'cleanup': report['cleanup'],
                          'fixtureId': report['fixtureId']}))
        return 0
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Import fixture failed or refused; no automatic retry.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
