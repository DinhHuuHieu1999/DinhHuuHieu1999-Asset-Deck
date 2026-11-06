import assert from 'node:assert/strict';
import test from 'node:test';
import {
  allowed,
  parseProxyArgs,
  validateConfig,
} from './client-https-proxy.mjs';

test('v4 proxy requires explicit capability and blocks writes/imports', () => {
  const args = [
    '--synthetic-only',
    '29542',
    '29543',
    'a'.repeat(32),
    'cert',
    'key',
  ];
  const config = parseProxyArgs([...args, '--export-v4-enabled']).config;
  assert.equal(config.exportV4Enabled, true);
  assert.equal(config.checkEnabled, true);
  assert.equal(config.exportV3Enabled, true);
  assert.equal(config.importEnabled, false);
  const route = (method, path, enabled = true) =>
    allowed(
      method,
      path,
      false,
      true,
      false,
      true,
      true,
      false,
      false,
      true,
      false,
      enabled,
    );
  assert.equal(allowed('GET', '/api/v1/assets/export/v4'), false);
  assert.equal(route('GET', '/api/v1/assets/export/v4'), true);
  assert.equal(route('GET', '/api/v1/assets/export/v4?q=forbidden'), true);
  assert.equal(route('GET', '/api/v1/assets/export/v4', false), false);
  for (const method of ['POST', 'PUT', 'DELETE']) {
    assert.equal(route(method, '/api/v1/assets/export/v4'), false);
    assert.equal(route(method, '/api/v1/assets/import/v3'), false);
  }
  for (const change of [
    { checkEnabled: false },
    { datesEnabled: false },
    { locationEnabled: false },
    { exportV3Enabled: false },
    { exportV4Enabled: 'true' },
    { importEnabled: true },
    { selectionExportEnabled: true },
  ])
    assert.throws(() => validateConfig({ ...config, ...change }));
  assert.equal(parseProxyArgs(args).config.exportV4Enabled, false);
});
