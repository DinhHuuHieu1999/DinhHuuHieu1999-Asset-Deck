import assert from 'node:assert/strict';
import test from 'node:test';
import { allowed, parseProxyArgs, validateConfig } from './client-https-proxy.mjs';

const path = '/api/v1/assets/12345678-1234-1234-1234-123456789abc/check-date';
const access = (method, url, enabled = true) => allowed(method, url, false, true, false, true, false, false, false, enabled);

test('check-date capability is opt-in and bounded to exact GET/PUT routes', () => {
  for (const method of ['GET', 'PUT']) {
    assert.equal(access(method, path), true);
    assert.equal(access(method, path, false), false);
    assert.equal(allowed(method, path), false);
  }
  for (const method of ['POST', 'DELETE', 'PATCH']) assert.equal(access(method, path), false);
  for (const url of [path + '?x=1', path + '/', path.replace('12345678', 'invalid'), 'https://localhost' + path]) {
    assert.equal(access('GET', url), false);
  }
});

test('dedicated CLI enables required dependencies without import/export capabilities', () => {
  const { config } = parseProxyArgs(['--synthetic-only', '29501', '29502', 'a'.repeat(32), 'synthetic.crt', 'synthetic.key', '--check-enabled']);
  assert.equal(config.checkEnabled, true);
  assert.equal(config.datesEnabled, true);
  assert.equal(config.locationEnabled, true);
  for (const name of ['importEnabled', 'importV2Enabled', 'importV3Enabled', 'exportV3Enabled', 'selectionExportEnabled']) {
    assert.equal(config[name], false);
    assert.throws(() => validateConfig({ ...config, [name]: true }));
  }
  for (const value of ['true', 1, null]) assert.throws(() => validateConfig({ ...config, checkEnabled: value }));
  for (const name of ['datesEnabled', 'locationEnabled']) assert.throws(() => validateConfig({ ...config, [name]: false }));
});
