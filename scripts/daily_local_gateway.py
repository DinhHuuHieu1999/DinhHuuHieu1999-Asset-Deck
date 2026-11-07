"""Daily gateway policy, independent of synthetic fixture fault injection."""

import re


HOP_HEADERS = frozenset(('connection', 'keep-alive', 'proxy-authenticate',
                         'proxy-authorization', 'te', 'trailer',
                         'transfer-encoding', 'upgrade'))
MAX_REQUEST = 2 * 1024 * 1024
MAX_RESPONSE = 16 * 1024 * 1024


class GatewayError(ValueError):
    """Public gateway failure without upstream content or private configuration."""


def filter_headers(headers):
    """Remove hop-by-hop headers, including Connection-nominated extensions."""
    pairs = list(headers)
    nominated = set()
    for key, value in pairs:
        if key.lower() == 'connection':
            nominated.update(part.strip().lower() for part in value.split(','))
    result = []
    for key, value in pairs:
        lower = key.lower()
        if lower in HOP_HEADERS or lower in nominated:
            continue
        if lower in ('host', 'content-length') or lower.startswith('x-forwarded-'):
            continue
        if lower == 'forwarded':
            continue
        if not re.fullmatch(r"[!#$%&'*+.^_`|~0-9A-Za-z-]+", key):
            raise GatewayError('Invalid header')
        if '\r' in value or '\n' in value or '\x00' in value:
            raise GatewayError('Invalid header')
        result.append((key, value))
    return result


def validate_request(method, target, headers, body):
    """Validate an origin-form API request; never interpret target as a host."""
    if method not in ('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'):
        raise GatewayError('Unsupported method')
    if (not isinstance(target, str) or not target.startswith('/api/v1/')
            or len(target) > 8192 or '#' in target or '\\' in target
            or any(ord(char) <= 32 or ord(char) >= 127 for char in target)):
        raise GatewayError('Invalid API target')
    path = target.split('?', 1)[0]
    if re.search(r'%(?:2e|2f|5c|00|0a|0d)', path, re.IGNORECASE):
        raise GatewayError('Ambiguous API path')
    if any(part in ('.', '..', '') for part in path[1:].split('/')):
        raise GatewayError('Ambiguous API path')
    if type(body) is not bytes or len(body) > MAX_REQUEST:
        raise GatewayError('Request size exceeded')
    pairs = list(headers)
    lengths = [value for key, value in pairs if key.lower() == 'content-length']
    if (len(lengths) > 1 or any(key.lower() == 'transfer-encoding' for key, _ in pairs)
            or (lengths and (not re.fullmatch(r'[0-9]+', lengths[0])
                             or int(lengths[0]) != len(body)))):
        raise GatewayError('Invalid request framing')
    return filter_headers(pairs)


def relay(method, target, headers, body, transport, timeout=15):
    """Relay via an injected fixed-loopback transport with bounded response size.

    Transport must enforce the supplied total deadline and must not follow redirects.
    This function does not open a socket, read TLS files, or log request contents.
    """
    if type(timeout) not in (int, float) or not 0 < timeout <= 30:
        raise GatewayError('Invalid transport deadline')
    forwarded = validate_request(method, target, headers, body)
    try:
        status, response_headers, response_body = transport(
            method, target, forwarded, body, timeout, MAX_RESPONSE)
        if type(status) is not int or not 200 <= status <= 599:
            raise GatewayError('Invalid upstream response')
        if type(response_body) is not bytes or len(response_body) > MAX_RESPONSE:
            raise GatewayError('Invalid upstream response')
        return status, filter_headers(response_headers), response_body
    except Exception:
        raise GatewayError('Upstream request failed') from None
