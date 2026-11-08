"""Opt-in sort HTTP/Dart acceptance using the existing owned TLS lifecycle."""
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

_spec = importlib.util.spec_from_file_location('sort_tls_lifecycle', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)
FILES = ('flutter/tool/check_sort_https_acceptance.dart',
         'flutter/tool/native_https_seed.dart', 'flutter/tool/client_https_acceptance.dart',
         'flutter/lib/api/asset_sort.dart', 'backend/src/domains/assets/asset-sort.ts',
         'backend/src/domains/assets/assets.dto.ts',
         'backend/dist/domains/assets/asset-sort.js',
         'backend/dist/domains/assets/assets.dto.js',
         'backend/dist/domains/assets/assets.repository.js',
         'backend/dist/domains/assets/asset-dates.repository.js',
         'flutter/lib/api/asset_api.dart', 'flutter/lib/api/asset_warranty.dart',
         'flutter/lib/api/asset_store.dart') + client.CHECK_FILES
FILES = tuple(dict.fromkeys(FILES))



class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a fixture marker or authenticated request to another target."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def preflight(root, args):
    """Validate all selected source before shared lifecycle side effects."""
    if any(not (root / name).is_file() for name in FILES):
        raise client.Refusal('Sort fixture source missing')
    client.preflight(root, args)


def validate_dart_result(value):
    """Only exact complete typed output satisfies the real-client stage."""
    expected = {'status': 'completed', 'syntheticOnly': True, 'checkSortAcceptance': True,
                'owners': 2, 'matchingRecords': 56, 'listPaths': 4, 'checkFilterCases': 12}
    if (not isinstance(value, dict) or value != expected or type(value.get('owners')) is not int or
            type(value.get('matchingRecords')) is not int or type(value.get('listPaths')) is not int or type(value.get('checkFilterCases')) is not int or value.get('checkSortAcceptance') is not True or value.get('syntheticOnly') is not True):
        raise client.Refusal('Sort Dart result incomplete')


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
                raise client.Refusal('Sort HTTP status/size mismatch')
            return json.loads(body)
    marker = request('/__asset_desk_fixture/' + identity)
    if marker != {'fixtureId': identity, 'syntheticOnly': True}:
        raise client.Refusal('Fixture marker mismatch')
    csrf = request('/api/v1/csrf-token')['token']
    suffix = secrets.token_hex(10)
    registered = request('/api/v1/auth/register', {'email': suffix+'@example.invalid',
        'username': 'v'+suffix, 'name': 'Synthetic DTO owner', 'password': 'Synthetic-'+suffix+'-42!'}, expected=201)
    token = registered['accessToken']
    for path in ('/api/v1/assets', '/api/v1/assets/warranty', '/api/v1/assets/locations/inventory'):
        for query in ('sort=invalid', 'sort=NAME_ASC', 'sort=name_asc&sort=updated_desc',
                      'sort%5Bnested%5D=name_asc', 'sort=name%20DESC%3BSELECT%201'):
            extra = 'warranty=expiring_soon&asOf=2027-02-01&' if path.endswith('/warranty') else ''
            request(path + '?' + extra + query, expected=400)
        for sort in ('updated_desc', 'name_asc', 'checked_asc'):
            value = request(path + '?' + urllib.parse.urlencode({'sort': sort, **({'warranty': 'expiring_soon', 'asOf': '2027-02-01'} if path.endswith('/warranty') else {})}))
            if value.get('items') != [] or value.get('nextOffset') is not None:
                raise client.Refusal('Unexpected validation-owner inventory')



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
        raise client.Refusal('Sort source changed during acceptance')
    return {'status': 'completed', 'syntheticOnly': True, 'sortHttpValidation': True,
            'sortDartClient': True, 'nativeAcceptance': 'pending'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--' + name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, default=0)
    args = parser.parse_args()
    args.check_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(), acceptance)
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Sort HTTPS fixture failed/refused; no automatic retry.')
        return 1
    print('Sort DTO and Dart HTTPS acceptance completed; native remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
