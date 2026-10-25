import test from 'node:test';
import assert from 'node:assert/strict';
import {
  allowed,
  cleanHeaders,
  createProxy,
  createHandler,
  validateConfig,
} from './client-https-proxy.mjs';
const config = { upstreamPort: 19001, fixtureId: 'a'.repeat(32) };
test('configuration refuses non-owned routing before TLS construction', () => {
  for (const upstreamPort of [0, 8180.5, 65536, '19001'])
    assert.throws(() => validateConfig({ ...config, upstreamPort }));
  for (const fixtureId of ['', '../secret', 'a'.repeat(31)])
    assert.throws(() => validateConfig({ ...config, fixtureId }));
  assert.throws(() => createProxy({}, { ...config, timeoutMs: 0 }));
});
test('route allowlist rejects arbitrary upstream and destructive methods', () => {
  assert.equal(allowed('GET', '/api/v1/assets?q=%25_'), true);
  assert.equal(allowed('POST', '/api/v1/auth/register'), true);
  for (const path of [
    'http://example.com/',
    '//example.com/',
    '/api/v1/assets/../auth',
    '/admin',
    '/api/v1/assets%2f',
  ])
    assert.equal(allowed('GET', path), false);
  assert.equal(allowed('DELETE', '/api/v1/assets'), false);
});
test('connection nominated headers removed without losing auth cookies', () => {
  assert.deepEqual(
    cleanHeaders({
      connection: 'x-private',
      'x-private': 'discard',
      host: 'external',
      authorization: 'synthetic',
      cookie: 'synthetic',
      'x-csrf-token': 'synthetic',
      'x-request-timestamp': '1',
    }),
    {
      authorization: 'synthetic',
      cookie: 'synthetic',
      'x-csrf-token': 'synthetic',
      'x-request-timestamp': '1',
    },
  );
});

// Stream-only tests: no listener, TLS material, backend, subprocess or network.
import { EventEmitter } from 'node:events';
import { Readable } from 'node:stream';

async function simulate({
  method = 'POST',
  url = '/api/v1/assets',
  chunks = [Buffer.from('{}')],
  status = 200,
  responseChunks = [Buffer.from('{}')],
  timeoutMs = 1000,
  hanging = false,
} = {}) {
  const req = hanging ? new Readable({ read() {} }) : Readable.from(chunks);
  Object.assign(req, {
    method,
    url,
    headers: {
      authorization: 'synthetic',
      cookie: 'csrf_token=synthetic',
      'x-csrf-token': 'synthetic',
      'x-request-timestamp': '1',
      host: 'untrusted',
    },
  });
  const res = new EventEmitter();
  res.headersSent = false;
  res.writableEnded = false;
  res.destroyed = false;
  res.writeHead = (code, headers) => {
    res.code = code;
    res.headers = headers;
    res.headersSent = true;
  };
  res.end = (body) => {
    res.body = body;
    res.writableEnded = true;
    res.emit('close');
  };
  res.destroy = () => {
    res.destroyed = true;
    res.emit('close');
  };
  let calls = 0,
    options,
    sent;
  const transport = (opts, callback) => {
    calls++;
    options = opts;
    const outgoing = new EventEmitter();
    outgoing.destroy = () => {};
    outgoing.end = (body) => {
      sent = body;
      queueMicrotask(() => {
        const incoming = Readable.from(responseChunks);
        incoming.statusCode = status;
        incoming.headers = {
          'content-type': 'application/json',
          connection: 'x-private',
          'x-private': 'discard',
        };
        callback(incoming);
      });
    };
    return outgoing;
  };
  const finished = new Promise((resolve) => res.once('close', resolve));
  await createHandler({ ...config, timeoutMs }, transport)(req, res);
  await finished;
  return { res, calls, options, sent };
}

test('stream proxy forwards only to fixed loopback with exact body and auth headers', async () => {
  const { res, calls, options, sent } = await simulate();
  assert.equal(calls, 1);
  assert.equal(options.hostname, '127.0.0.1');
  assert.equal(options.port, config.upstreamPort);
  assert.equal(options.headers.authorization, 'synthetic');
  assert.equal(options.headers.cookie, 'csrf_token=synthetic');
  assert.equal(options.headers['x-csrf-token'], 'synthetic');
  assert.equal(options.headers['x-request-timestamp'], '1');
  assert.equal(options.headers.host, undefined);
  assert.equal(sent.toString(), '{}');
  assert.equal(res.code, 200);
  assert.equal(res.headers['x-private'], undefined);
});
test('identity marker and denied routes never contact upstream', async () => {
  const marker = await simulate({
    method: 'GET',
    url: `/__asset_desk_fixture/${config.fixtureId}`,
  });
  assert.equal(marker.calls, 0);
  assert.deepEqual(JSON.parse(marker.res.body), {
    fixtureId: config.fixtureId,
    syntheticOnly: true,
  });
  const denied = await simulate({ method: 'DELETE' });
  assert.equal(denied.calls, 0);
  assert.equal(denied.res.code, 404);
});
test('oversized request is refused before contacting upstream', async () => {
  const result = await simulate({ chunks: [Buffer.alloc(1024 * 1024 + 1)] });
  assert.equal(result.calls, 0);
  assert.equal(result.res.code, 413);
});
test('oversized upstream response and redirect fail without exposing response', async () => {
  for (const options of [
    { responseChunks: [Buffer.alloc(1024 * 1024 + 1)] },
    { status: 302, responseChunks: [Buffer.from('private')] },
  ]) {
    const result = await simulate(options);
    assert.equal(result.calls, 1);
    assert.equal(result.res.code, 502);
    assert.equal(result.res.body.includes('private'), false);
  }
});
test('incomplete body hits total deadline without contacting upstream', async () => {
  const result = await simulate({ hanging: true, timeoutMs: 10 });
  assert.equal(result.calls, 0);
  assert.equal(result.res.code, 504);
});

import backendReadiness from './client-https-backend.cjs';
test('backend readiness is written only after the exact server binds', () => {
  const expected = { fixtureId: config.fixtureId, port: 19002 };
  for (const address of [
    null,
    { address: '0.0.0.0', port: 19002 },
    { address: '127.0.0.1', port: 1 },
    { address: '127.0.0.1', port: 19002 },
  ]) {
    const server = new EventEmitter();
    server.address = () => address;
    const writes = [];
    backendReadiness.watch(server, expected, (...args) => writes.push(args));
    assert.equal(writes.length, 0);
    server.emit('listening');
    const matches = address?.address === '127.0.0.1' && address?.port === 19002;
    assert.equal(writes.length, matches ? 1 : 0);
    if (matches) {
      assert.deepEqual(JSON.parse(writes[0][1]), {
        fixtureId: config.fixtureId,
        pid: process.pid,
        port: 19002,
      });
      assert.equal(writes[0][2].flag, 'wx');
    }
  }
});

test('inventory export is an exact GET-only fixture route', () => {
  assert.equal(allowed('GET', '/api/v1/assets/export'), true);
  assert.equal(
    allowed('GET', '/api/v1/assets/export?q=missing&owner=synthetic'),
    true,
  );
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE'])
    assert.equal(allowed(method, '/api/v1/assets/export'), false);
  for (const path of [
    '/api/v1/assets/export/other',
    '/api/v1/assets/export/',
    '/api/v1/assets/%65xport',
    '/api/v1/assets/export/../auth',
  ])
    assert.equal(allowed('GET', path), false);
});

test('export forwarding preserves upstream 200, 401 and 422 without retry', async () => {
  const url = '/api/v1/assets/export?q=missing&owner=synthetic';
  for (const status of [200, 401, 422]) {
    const payload = Buffer.from(JSON.stringify({ synthetic: true, status }));
    const result = await simulate({
      method: 'GET',
      url,
      chunks: [],
      status,
      responseChunks: [payload],
    });
    assert.equal(result.calls, 1);
    assert.equal(result.options.path, url);
    assert.equal(result.options.method, 'GET');
    assert.equal(result.options.hostname, '127.0.0.1');
    assert.equal(result.options.headers.authorization, 'synthetic');
    assert.equal(result.sent.length, 0);
    assert.equal(result.res.code, status);
    assert.deepEqual(result.res.body, payload);
    assert.equal(result.res.headers['cache-control'], 'no-store');
  }
});
