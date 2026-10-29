import assert from 'node:assert/strict';
import test from 'node:test';
import {
  allowed,
  parseProxyArgs,
  validateConfig,
} from './client-https-proxy.mjs';

const args = [
  '--synthetic-only',
  '29542',
  '29543',
  'a'.repeat(32),
  'cert',
  'key',
];
const route = '/api/v1/assets/export/selection';

test('selection proxy is explicit and does not enable imports', () => {
  const config = parseProxyArgs([...args, '--selection-export-enabled']).config;
  assert.equal(config.selectionExportEnabled, true);
  for (const key of ['datesEnabled', 'locationEnabled', 'exportV3Enabled'])
    assert.equal(config[key], true);
  for (const key of ['importEnabled', 'importV2Enabled', 'importV3Enabled'])
    assert.equal(config[key], false);
  for (const flag of [
    undefined,
    '--export-v3-enabled',
    '--import-v3-enabled',
    '--location-enabled',
  ]) {
    assert.equal(
      parseProxyArgs(flag ? [...args, flag] : args).config
        .selectionExportEnabled,
      false,
    );
  }
  for (const change of [
    { selectionExportEnabled: 'true' },
    { datesEnabled: false },
    { locationEnabled: false },
    { exportV3Enabled: false },
    { importEnabled: true },
    { importV2Enabled: true },
    { importV3Enabled: true },
  ]) {
    assert.throws(() => validateConfig({ ...config, ...change }));
  }
});

test('selection routing accepts GET only and requires its own capability', () => {
  assert.equal(allowed('GET', route), false);
  assert.equal(allowed('GET', route, false, true, false, true, true), false);
  for (const path of [route, `${route}?q=%25_&sort=name_asc`]) {
    assert.equal(
      allowed('GET', path, false, true, false, true, true, false, true),
      true,
    );
    for (const method of ['POST', 'PUT', 'DELETE']) {
      assert.equal(
        allowed(method, path, false, true, false, true, true, false, true),
        false,
      );
    }
  }
  assert.equal(
    allowed(
      'GET',
      `${route}/extra`,
      false,
      true,
      false,
      true,
      true,
      false,
      true,
    ),
    false,
  );
  assert.equal(
    allowed(
      'POST',
      '/api/v1/assets/import/v3',
      false,
      true,
      false,
      true,
      true,
      false,
      true,
    ),
    false,
  );
});
