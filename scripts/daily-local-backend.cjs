'use strict';

/** Own one backend instance and close it on private stdin shutdown or EOF. */
async function supervise(bootstrap, input, notify = () => {}) {
  let closing = false;
  let buffer = '';
  let app;
  let finish;
  let reject;
  const done = new Promise((resolve, fail) => {
    finish = resolve;
    reject = fail;
  });
  // Attach a rejection handler before an asynchronous startup can fail.
  done.catch(() => {});
  async function close() {
    if (closing) return;
    closing = true;
    if (!app) return;
    try {
      await app.close();
      notify('stopped');
      finish();
    } catch {
      reject(new Error('Backend shutdown failed'));
    }
  }
  function onData(chunk) {
    buffer += chunk.toString('utf8');
    if (buffer.length > 64 || buffer.includes('\n')) {
      // No command other than shutdown is accepted; invalid input also closes.
      void close();
    }
  }
  input.on('data', onData);
  input.on('end', close);
  input.on('error', close);
  try {
    app = await bootstrap();
    if (closing) {
      closing = false;
      await close();
    } else {
      notify('ready');
    }
    await done;
  } finally {
    input.removeListener('data', onData);
    input.removeListener('end', close);
    input.removeListener('error', close);
  }
}

module.exports = { supervise };
if (require.main === module) {
  // The adapter selects the backend working directory; no caller-controlled module URL.
  const path = require('node:path');
  const { bootstrap } = require(path.join(process.cwd(), 'dist', 'main.js'));
  void supervise(bootstrap, process.stdin, (event) => {
    if (event === 'ready') process.stdout.write('ASSET_DESK_READY\n');
  }).catch(() => {
    console.error('Asset Desk supervised backend failed');
    process.exitCode = 1;
  });
}
