"""Opt-in serial HTTP/Dart acceptance using the existing owned TLS lifecycle."""
import argparse
import hashlib
import http.cookiejar
import importlib.util
import json
from pathlib import Path
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

_spec = importlib.util.spec_from_file_location('serial_tls_lifecycle', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)
FILES = ('flutter/tool/serial_https_acceptance.dart',
         'flutter/lib/api/asset_serial_check.dart',
         'backend/src/domains/assets/assets.controller.ts',
         'backend/src/domains/assets/assets.service.ts',
         'backend/src/domains/assets/assets.repository.ts',
         'backend/src/domains/assets/assets.dto.ts',
         'backend/dist/domains/assets/assets.controller.js',
         'backend/dist/domains/assets/assets.service.js',
         'backend/dist/domains/assets/assets.repository.js',
         'backend/dist/domains/assets/assets.dto.js',
         'flutter/lib/api/asset_api.dart',
         'flutter/tool/native_https_seed.dart',
         'flutter/tool/client_https_acceptance.dart') + client.LOCATION_FILES



class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a fixture marker or authenticated request to another target."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def preflight(root, args):
    """Validate all selected source before shared lifecycle side effects."""
    if any(not (root / name).is_file() for name in FILES):
        raise client.Refusal('Serial fixture source missing')
    client.preflight(root, args)


def validate_dart_result(value):
    """Only exact complete typed output satisfies the real-client stage."""
    expected = {'status': 'completed', 'syntheticOnly': True, 'serialAcceptance': True,
                'owners': 2, 'readOnlySnapshots': 2}
    if (not isinstance(value, dict) or value != expected or type(value.get('owners')) is not int or
            type(value.get('readOnlySnapshots')) is not int or value.get('serialAcceptance') is not True or value.get('syntheticOnly') is not True):
        raise client.Refusal('Serial Dart result incomplete')


def dto_acceptance(args, runtime, identity):
    """Exercise actual HTTP validation; never print account or token material."""
    base = 'https://localhost:%s' % args.tls_port
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    token = None
    csrf = None
    def request(path, data=None, expected=200):
        headers = {'Accept': 'application/json', 'x-request-timestamp': str(int(time.time()*1000))}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        raw = None
        if data is not None:
            headers.update({'Content-Type': 'application/json', 'x-csrf-token': csrf})
            raw = json.dumps(data).encode()
        req = urllib.request.Request(base + path, data=raw, headers=headers)
        try:
            response = opener.open(req, timeout=min(10, runtime.remaining()))
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read(1024*1024+1)
            if response.status != expected or len(body) > 1024*1024:
                raise client.Refusal('Serial HTTP status/size mismatch')
            if expected == 200 and path.startswith('/api/v1/assets/serial-duplicates') and response.headers.get('Cache-Control') != 'no-store':
                raise client.Refusal('Serial cache policy mismatch')
            return json.loads(body)
    marker = request('/__asset_desk_fixture/' + identity)
    if marker != {'fixtureId': identity, 'syntheticOnly': True}:
        raise client.Refusal('Fixture marker mismatch')
    request('/api/v1/assets/serial-duplicates?serial=probe', expected=401)
    csrf = request('/api/v1/csrf-token')['token']
    suffix = secrets.token_hex(10)
    registered = request('/api/v1/auth/register', {'email': suffix+'@example.invalid',
        'username': 'v'+suffix, 'name': 'Synthetic DTO owner',
        'password': 'Synthetic-'+suffix+'-42!'}, expected=201)
    token = registered['accessToken']
    for query in ('serial=a&serial=b', 'serial%5Bnested%5D=a',
                  'serial=a&excludeId=invalid', 'serial='+'a'*121, 'serial=%00'):
        request('/api/v1/assets/serial-duplicates?' + query, expected=400)
    for value in ('', '%_literal', 'AbC', "' OR 1=1 --"):
        result = request('/api/v1/assets/serial-duplicates?' +
                         urllib.parse.urlencode({'serial': value}))
        if result != {'duplicate': False} or type(result.get('duplicate')) is not bool:
            raise client.Refusal('Unexpected serial response')




def source_hashes(root):
    """Hash only fixed public sources and artifacts, never TLS or env values."""
    return {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in FILES}


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Run DTO then real Dart checks once; shared lifecycle owns shutdown."""
    before = source_hashes(root)
    dto_acceptance(args, runtime, identity)
    output = runtime.run([args.dart, '--disable-dart-dev', str(root / FILES[0]),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity],
                         cwd=root / 'flutter')
    validate_dart_result(json.loads(output))
    if source_hashes(root) != before:
        raise client.Refusal('Serial source changed during acceptance')
    return {'status': 'completed', 'syntheticOnly': True, 'serialHttpValidation': True,
            'serialDartClient': True, 'nativeAcceptance': 'pending'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--' + name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, default=0)
    args = parser.parse_args()
    args.location_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(), acceptance)
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Serial HTTPS fixture failed/refused; no automatic retry.')
        return 1
    print('Serial DTO and Dart HTTPS acceptance completed; native remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
