import { readFileSync } from 'node:fs';
import { createProxy, validateConfig } from './client-https-proxy.mjs';

// The reviewed bootstrap is the only caller; importing the proxy module is inert.
const [optIn, upstream, listen, fixtureId, cert, key] = process.argv.slice(2);
try {
  if (optIn !== '--synthetic-only' || process.argv.length !== 8)
    throw new Error('Explicit opt-in required');
  const config = { upstreamPort: Number(upstream), fixtureId };
  validateConfig(config);
  const port = Number(listen);
  if (
    !Number.isInteger(port) ||
    port < 1024 ||
    port > 65535 ||
    port === config.upstreamPort
  )
    throw new Error('Invalid port');
  const server = createProxy(
    { cert: readFileSync(cert), key: readFileSync(key) },
    config,
  );
  server.on('error', () => {
    process.exitCode = 1;
    server.close();
  });
  server.listen(port, '127.0.0.1');
  process.on('SIGTERM', () => {
    server.closeAllConnections();
    server.close();
  });
} catch {
  process.stderr.write('Fixture TLS startup refused\n');
  process.exitCode = 1;
}
