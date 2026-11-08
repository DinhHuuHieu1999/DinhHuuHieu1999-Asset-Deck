import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';

const require = createRequire(
  new URL('../backend/package.json', import.meta.url),
);
const ts = require('typescript');
const source = readFileSync(
  new URL(
    '../backend/src/domains/assets/asset-serial.postgres.spec.ts',
    import.meta.url,
  ),
  'utf8',
);
const compiled = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
  },
}).outputText;

function loadFixture(environment, query) {
  let setup;
  let cleanup;
  let constructed = 0;
  let ended = 0;
  class Pool {
    constructor() {
      constructed += 1;
    }
    query(...args) {
      return query(...args);
    }
    async end() {
      ended += 1;
    }
  }
  const describe = (_name, callback) => callback();
  describe.skip = () => {};
  const context = {
    exports: {},
    URL,
    process: { env: environment },
    require: (name) => {
      if (name === 'node:crypto')
        return { randomBytes: (size) => Buffer.alloc(size) };
      if (name === 'pg') return { Pool };
      if (name === './assets.repository') return { AssetsRepository: class {} };
      throw new Error(`Unexpected fixture import: ${name}`);
    },
    describe,
    beforeAll: (callback) => {
      setup = callback;
    },
    afterAll: (callback) => {
      cleanup = callback;
    },
    it: () => {},
  };
  vm.runInNewContext(compiled, context, { timeout: 1000 });
  return { setup, cleanup, stats: () => ({ constructed, ended }) };
}
const identity = {
  ASSET_SERIAL_FIXTURE_OPT_IN: 'isolated-serial-v1',
  ASSET_SERIAL_FIXTURE_URL:
    'postgres://synthetic:synthetic@127.0.0.1:29499/asset_serial_fixture_aaaaaaaaaaaa',
  ASSET_SERIAL_FIXTURE_MARKER: 'a'.repeat(32),
};

test('default fixture remains skipped and constructs no pool', () => {
  const fixture = loadFixture({}, () => {
    throw new Error('Unexpected query');
  });
  assert.equal(fixture.setup, undefined);
  assert.equal(fixture.cleanup, undefined);
  assert.deepEqual(fixture.stats(), { constructed: 0, ended: 0 });
});
test('validation failure before pool creation leaves cleanup safe', async () => {
  const fixture = loadFixture(
    { ASSET_SERIAL_FIXTURE_OPT_IN: 'isolated-serial-v1' },
    () => {
      throw new Error('Unexpected query');
    },
  );
  await assert.rejects(fixture.setup, /Explicit fixture identity required/);
  await fixture.cleanup();
  assert.deepEqual(fixture.stats(), { constructed: 0, ended: 0 });
});
test('database mismatch after pool creation still closes the pool', async () => {
  const fixture = loadFixture(identity, async () => ({
    rows: [{ name: 'wrong_database' }],
  }));
  await assert.rejects(fixture.setup, /Database mismatch/);
  await fixture.cleanup();
  assert.deepEqual(fixture.stats(), { constructed: 1, ended: 1 });
});
test('query rejection after pool creation still closes the pool', async () => {
  const fixture = loadFixture(identity, async () => {
    throw new Error('Synthetic query failure');
  });
  await assert.rejects(fixture.setup, /Synthetic query failure/);
  await fixture.cleanup();
  assert.deepEqual(fixture.stats(), { constructed: 1, ended: 1 });
});
