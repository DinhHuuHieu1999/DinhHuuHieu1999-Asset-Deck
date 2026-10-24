const http = require('node:http');
const { writeFileSync } = require('node:fs');
const path = require('node:path');

/** Emit readiness only from the server that actually bound the expected port. */
function watch(server, expected, write = writeFileSync) {
  server.once('listening', () => {
    const address = server.address();
    if (
      !address ||
      address.address !== '127.0.0.1' ||
      address.port !== expected.port
    )
      return;
    write(
      path.join(process.cwd(), 'backend-ready.json'),
      JSON.stringify({
        fixtureId: expected.fixtureId,
        pid: process.pid,
        port: address.port,
      }),
      { encoding: 'utf8', flag: 'wx' },
    );
  });
}

/** Install only inside the opt-in fixture child, never the product entrypoint. */
function install(env = process.env) {
  const fixtureId = env.ASSET_DESK_FIXTURE_ID;
  const port = Number(env.BACKEND_HTTP_PORT);
  if (
    !/^[a-f0-9]{32}$/.test(fixtureId ?? '') ||
    !Number.isInteger(port) ||
    port < 1024 ||
    port > 65535
  )
    throw new Error('Invalid fixture identity');
  const original = http.Server.prototype.listen;
  http.Server.prototype.listen = function (...args) {
    watch(this, { fixtureId, port });
    return original.apply(this, args);
  };
}

module.exports = { watch, install };
if (process.env.ASSET_DESK_FIXTURE_ID) install();
