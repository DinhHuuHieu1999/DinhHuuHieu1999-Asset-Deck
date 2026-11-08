"""Opt-in saved filters HTTPS/Dart acceptance using the existing owned TLS lifecycle."""
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

_spec = importlib.util.spec_from_file_location('saved_filters_tls_lifecycle', Path(__file__).with_name('client-https-fixture.py'))
client = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(client)
FILES = ('flutter/tool/saved_filters_https_acceptance.dart', 'flutter/lib/api/asset_saved_filter.dart',
         'backend/migrations/007-asset-saved-filters.sql') + client.CHECK_FILES
FILES = tuple(dict.fromkeys(FILES))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a fixture marker or authenticated request to another target."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def preflight(root, args):
    """Validate all selected source before shared lifecycle side effects."""
    if any(not (root / name).is_file() for name in FILES):
        raise client.Refusal('Saved filters fixture source missing')
    client.preflight(root, args)


def validate_dart_result(value):
    """Only exact complete typed output satisfies the real-client stage."""
    expected = {'status': 'completed', 'syntheticOnly': True, 'savedFiltersAcceptance': True,
                'owners': 2, 'mutations': 3}
    if (not isinstance(value, dict) or value != expected or
            type(value.get('owners')) is not int or type(value.get('mutations')) is not int or
            value.get('syntheticOnly') is not True or value.get('savedFiltersAcceptance') is not True):
        raise client.Refusal('Saved filters Dart result incomplete')


def security_acceptance(args, runtime, identity):
    """Assert actual unauthenticated and missing-CSRF refusal without catalog writes."""
    base = 'https://localhost:%s' % args.tls_port
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    token = None
    csrf = None

    def request(path, expected, method='GET', data=None, send_csrf=True):
        headers = {'Accept': 'application/json', 'x-request-timestamp': str(int(time.time()*1000))}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        if send_csrf and csrf:
            headers['x-csrf-token'] = csrf
        raw = None
        if data is not None:
            headers['Content-Type'] = 'application/json'
            raw = json.dumps(data).encode()
        req = urllib.request.Request(base + path, data=raw, headers=headers, method=method)
        try:
            response = opener.open(req, timeout=min(10, runtime.remaining()))
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read(1024*1024+1)
            if response.status != expected or len(body) > 1024*1024:
                raise client.Refusal('Saved filters HTTP status/size mismatch')
            return json.loads(body)

    if request('/__asset_desk_fixture/' + identity, 200) != {'fixtureId':identity, 'syntheticOnly':True}:
        raise client.Refusal('Fixture marker mismatch')
    path = '/api/v1/inventory-saved-filters'
    request(path, 401)
    csrf = request('/api/v1/csrf-token', 200)['token']
    suffix = secrets.token_hex(10)
    registered = request('/api/v1/auth/register', 201, 'POST', {
        'email':suffix+'@example.invalid', 'username':'s'+suffix,
        'name':'Synthetic security owner', 'password':'Synthetic-'+suffix+'-42!'})
    token = registered['accessToken']
    query = dict(q='', status='', category='', sort='updated_desc', locationMode='all',
                 location='', warranty='all', asOf='', checkMode='all', checkBefore='', checkOnOrAfter='')
    target = path + '/11111111-1111-4111-8111-111111111111'
    for method, url, body in [('POST',path,dict(name='Never created',schemaVersion=1,query=query)),
                              ('PUT',target,dict(name='Never updated',schemaVersion=1,query=query,version=1)),
                              ('DELETE',target,dict(version=1))]:
        request(url, 403, method, body, send_csrf=False)
    if request(path, 200) != {'items':[]}:
        raise client.Refusal('Security refusal changed saved definitions')


def source_hashes(root):
    """Hash only fixed public sources and artifacts, never TLS or env values."""
    return {name: hashlib.sha256((root/name).read_bytes()).hexdigest() for name in FILES}


def acceptance(root, args, runtime, folder, identity, backend, proxy):
    """Run real Dart checks once; shared lifecycle owns shutdown."""
    before = source_hashes(root)
    security_acceptance(args, runtime, identity)
    output = runtime.run([args.dart, '--disable-dart-dev', str(root / FILES[0]),
                          '--synthetic-only', 'https://localhost:%s/api/v1' % args.tls_port, identity],
                         cwd=root / 'flutter')
    validate_dart_result(json.loads(output))
    if source_hashes(root) != before:
        raise client.Refusal('Saved filters source changed during acceptance')
    return {'status': 'completed', 'syntheticOnly': True, 'savedFiltersDartClient': True, 'savedFiltersSecurityRefusal': True, 'nativeAcceptance': 'pending'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    for name in ('image', 'cert', 'key', 'dart'):
        parser.add_argument('--' + name, default='')
    for name in ('db-port', 'backend-port', 'tls-port'):
        parser.add_argument('--' + name, type=int, default=0)
    args = parser.parse_args()
    args.check_mode = True
    args.saved_filters_mode = True
    root = Path(__file__).resolve().parent.parent
    try:
        preflight(root, args)
        client.execute(root, args, client.Runtime(), acceptance)
    except (client.Refusal, OSError, ValueError, KeyError, TypeError):
        print('Saved filters HTTPS fixture failed/refused; no automatic retry.')
        return 1
    print('Saved filters Dart HTTPS acceptance completed; native remains pending.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
