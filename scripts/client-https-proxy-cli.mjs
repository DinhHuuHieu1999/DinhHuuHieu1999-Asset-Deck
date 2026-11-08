import { readFileSync } from 'node:fs';
import { createProxy, parseProxyArgs } from './client-https-proxy.mjs';

// The reviewed bootstrap is the only caller; importing the proxy module is inert.
try {
  const { config, port, cert, key } = parseProxyArgs(process.argv.slice(2));
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
