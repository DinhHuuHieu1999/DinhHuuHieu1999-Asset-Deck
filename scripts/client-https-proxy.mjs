import https from 'node:https';
import http from 'node:http';

const limit = 1024 * 1024;
const hop = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

/** Validate fixed fixture routing before creating a server or reading TLS files. */
export function validateConfig({
  upstreamPort,
  fixtureId,
  timeoutMs = 15000,
  importEnabled = false,
}) {
  if (
    typeof importEnabled !== 'boolean' ||
    !Number.isInteger(upstreamPort) ||
    upstreamPort < 1024 ||
    upstreamPort > 65535 ||
    !/^[a-f0-9]{32}$/.test(fixtureId) ||
    !Number.isInteger(timeoutMs) ||
    timeoutMs < 1 ||
    timeoutMs > 30000
  ) {
    throw new Error('Invalid fixture configuration');
  }
}

/** Parse the fixed fixture CLI; optional import capability must be explicit. */
export function parseProxyArgs(args) {
  if (
    !Array.isArray(args) ||
    ![6, 7].includes(args.length) ||
    args[0] !== '--synthetic-only' ||
    (args.length === 7 && args[6] !== '--import-enabled')
  )
    throw new Error('Explicit fixture opt-in required');
  const [, upstream, listen, fixtureId, cert, key] = args;
  const config = {
    upstreamPort: Number(upstream),
    fixtureId,
    importEnabled: args.length === 7,
  };
  validateConfig(config);
  const port = Number(listen);
  if (
    !Number.isInteger(port) ||
    port < 1024 ||
    port > 65535 ||
    port === config.upstreamPort ||
    !cert ||
    !key
  )
    throw new Error('Invalid fixture arguments');
  return { config, port, cert, key };
}

/** Allow only the API operations exercised by the synthetic client. */
export function allowed(method, raw, importEnabled = false) {
  if (typeof raw !== 'string' || !raw.startsWith('/') || raw.startsWith('//'))
    return false;
  if (method === 'POST' && raw === '/api/v1/assets/import')
    return importEnabled === true;
  const path = raw.split('?')[0];
  if (method === 'GET')
    return [
      '/api/v1/csrf-token',
      '/api/v1/auth/profile',
      '/api/v1/assets',
      '/api/v1/assets/export',
    ].includes(path);
  if (method === 'POST')
    return [
      '/api/v1/auth/register',
      '/api/v1/auth/login',
      '/api/v1/assets',
    ].includes(path);
  return method === 'PUT' && /^\/api\/v1\/assets\/[a-f0-9-]{36}$/i.test(path);
}

/** Remove hop headers, including headers nominated by Connection. */
export function cleanHeaders(headers) {
  const excluded = new Set([
    ...hop,
    ...String(headers.connection ?? '')
      .toLowerCase()
      .split(',')
      .map((v) => v.trim()),
    'host',
  ]);
  return Object.fromEntries(
    Object.entries(headers).filter(([key]) => !excluded.has(key.toLowerCase())),
  );
}

/** Build bounded routing with an injectable transport for offline contract tests. */
export function createHandler(config, request = http.request) {
  validateConfig(config);
  const { upstreamPort, fixtureId, timeoutMs = 15000 } = config;
  return async (req, res) => {
    const fail = (code) => {
      if (res.writableEnded || res.destroyed) return;
      if (!res.headersSent) {
        res.writeHead(code, {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        });
        res.end('{"error":"Fixture request failed"}');
      } else res.destroy();
    };
    const timer = setTimeout(() => {
      fail(504);
      req.destroy();
    }, timeoutMs);
    let upstream;
    res.on('close', () => {
      clearTimeout(timer);
      upstream?.destroy();
    });
    if (
      req.method === 'GET' &&
      req.url === `/__asset_desk_fixture/${fixtureId}`
    ) {
      res.writeHead(200, {
        'content-type': 'application/json',
        'cache-control': 'no-store',
      });
      res.end(JSON.stringify({ fixtureId, syntheticOnly: true }));
      return;
    }
    if (!allowed(req.method, req.url, config.importEnabled)) {
      fail(404);
      req.resume();
      return;
    }
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req.iterator({ destroyOnReturn: false })) {
        size += chunk.length;
        if (size > limit) {
          // Do not tear down the shared socket before the error is flushed.
          // Returning from the default async iterator would also destroy req.
          req.pause();
          res.once('finish', () => req.destroy());
          fail(413);
          return;
        }
        chunks.push(chunk);
      }
      const body = Buffer.concat(chunks);
      upstream = request(
        {
          hostname: '127.0.0.1',
          port: upstreamPort,
          path: req.url,
          method: req.method,
          headers: {
            ...cleanHeaders(req.headers),
            'content-length': body.length,
          },
          agent: false,
        },
        (incoming) => {
          const parts = [];
          let bytes = 0;
          incoming.on('data', (chunk) => {
            bytes += chunk.length;
            if (bytes > limit) {
              fail(502);
              upstream.destroy();
            } else parts.push(chunk);
          });
          incoming.on('error', () => fail(502));
          incoming.on('end', () => {
            if (res.writableEnded || res.destroyed) return;
            if (incoming.statusCode >= 300 && incoming.statusCode < 400) {
              fail(502);
              return;
            }
            const output = Buffer.concat(parts);
            res.writeHead(incoming.statusCode, {
              ...cleanHeaders(incoming.headers),
              'content-length': output.length,
              'cache-control': 'no-store',
            });
            res.end(output);
          });
        },
      );
      upstream.on('error', () => fail(502));
      upstream.end(body);
    } catch {
      fail(502);
    }
  };
}

/** Create an inert TLS server; caller explicitly owns listen/close and TLS loading. */
export function createProxy(tls, config) {
  validateConfig(config);
  const timeoutMs = config.timeoutMs ?? 15000;
  const server = https.createServer(tls, createHandler(config));
  server.requestTimeout = timeoutMs;
  server.headersTimeout = timeoutMs;
  server.timeout = timeoutMs;
  return server;
}
