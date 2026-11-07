"""Synthetic-only HTTPS acceptance client; no insecure TLS or proxy fallback."""

import http.client
import http.cookiejar
import json
import secrets
import ssl
import time
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Do not forward authentication material to a redirect target."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class SyntheticClient:
    """Create one synthetic account and verify its asset across backend restart."""

    def __init__(self, port, remaining, opener=None):
        if type(port) is not int or not 1024 <= port <= 65535:
            raise ValueError('Invalid fixture TLS port')
        self.port = port
        self.remaining = remaining
        self.opener = opener or urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect(),
            urllib.request.HTTPSHandler(context=ssl.create_default_context()),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        suffix = secrets.token_hex(10)
        self.account = dict(email=suffix + '@example.invalid', username='daily' + suffix,
                            name='Synthetic daily owner', password='Synthetic-' + suffix + '-42!')
        self.token = None
        self.csrf = None
        self.asset = dict(name='Synthetic daily asset', category='fixture',
                          serial='DAILY-%_1', status='stored', notes='Synthetic acceptance only')

    def request(self, path, data=None, expected=200):
        """Send only to the fixed TLS endpoint; never log request/response bodies."""
        if not path.startswith('/api/v1/') or '\r' in path or '\n' in path:
            raise ValueError('Invalid fixture API path')
        headers = {'Accept': 'application/json',
                   'x-request-timestamp': str(int(time.time() * 1000))}
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
        raw = None
        if data is not None:
            headers['Content-Type'] = 'application/json'
            headers['x-csrf-token'] = self.csrf or ''
            raw = json.dumps(data).encode('utf-8')
        request = urllib.request.Request('https://localhost:{}{}'.format(self.port, path),
                                         data=raw, headers=headers)
        try:
            response = self.opener.open(request, timeout=min(10, self.remaining()))
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read(1024 * 1024 + 1)
            if response.status != expected or len(body) > 1024 * 1024:
                raise RuntimeError('Synthetic HTTPS response mismatch')
            return json.loads(body)

    def create_synthetic_asset(self):
        """Use the normal security middleware; never seed around API validation."""
        self.csrf = self.request('/api/v1/csrf-token')['token']
        self.token = self.request('/api/v1/auth/register', self.account, 201)['accessToken']
        result = self.request('/api/v1/assets', self.asset, 201)
        if not isinstance(result.get('id'), str) or any(result.get(k) != v for k, v in self.asset.items()):
            raise RuntimeError('Synthetic asset creation mismatch')
        return result['id']

    def login_and_assert_asset(self, asset_id):
        """Reauthenticate after restart and compare the same asset, not just count."""
        self.token = None
        self.csrf = self.request('/api/v1/csrf-token')['token']
        self.token = self.request('/api/v1/auth/login',
                                  {'identifier': self.account['email'], 'password': self.account['password']})['accessToken']
        result = self.request('/api/v1/assets')
        items = result.get('items')
        if (not isinstance(items, list) or len(items) != 1 or items[0].get('id') != asset_id
                or any(items[0].get(k) != v for k, v in self.asset.items())):
            raise RuntimeError('Synthetic restart persistence mismatch')

    def assert_invalid_requests_rejected(self):
        """Exercise raw duplicate and foreign Host without relying on URL rewriting."""
        for hosts in ([], ['foreign.invalid'], ['localhost:' + str(self.port)] * 2):
            connection = http.client.HTTPSConnection('localhost', self.port,
                context=ssl.create_default_context(), timeout=min(5, self.remaining()))
            try:
                connection.putrequest('GET', '/api/v1/assets', skip_host=True)
                for host in hosts:
                    connection.putheader('Host', host)
                connection.endheaders()
                response = connection.getresponse()
                if response.status != 400:
                    raise RuntimeError('Synthetic Host rejection mismatch')
                response.read(1024)
            finally:
                connection.close()
