import assert from 'node:assert/strict';
import test from 'node:test';
import {
  allowed,
  parseProxyArgs,
  validateConfig,
} from './client-https-proxy.mjs';

const path = '/api/v1/assets/12345678-1234-1234-1234-123456789abc/check-date';
const access = (method, url, enabled = true) =>
  allowed(method, url, false, true, false, true, false, false, false, enabled);

test('check-date capability is opt-in and bounded to exact GET/PUT routes', () => {
  for (const method of ['GET', 'PUT']) {
    assert.equal(access(method, path), true);
    assert.equal(access(method, path, false), false);
    assert.equal(allowed(method, path), false);
  }
  for (const method of ['POST', 'DELETE', 'PATCH'])
    assert.equal(access(method, path), false);
  for (const url of [
    path + '?x=1',
    path + '/',
    path.replace('12345678', 'invalid'),
    'https://localhost' + path,
  ]) {
    assert.equal(access('GET', url), false);
  }
});

test('dedicated CLI enables required dependencies without import/export capabilities', () => {
  const { config } = parseProxyArgs([
    '--synthetic-only',
    '29501',
    '29502',
    'a'.repeat(32),
    'synthetic.crt',
    'synthetic.key',
    '--check-enabled',
  ]);
  assert.equal(config.checkEnabled, true);
  assert.equal(config.datesEnabled, true);
  assert.equal(config.locationEnabled, true);
  for (const name of [
    'importEnabled',
    'importV2Enabled',
    'importV3Enabled',
    'exportV3Enabled',
    'selectionExportEnabled',
  ]) {
    assert.equal(config[name], false);
    assert.throws(() => validateConfig({ ...config, [name]: true }));
  }
  for (const value of ['true', 1, null])
    assert.throws(() => validateConfig({ ...config, checkEnabled: value }));
  for (const name of ['datesEnabled', 'locationEnabled'])
    assert.throws(() => validateConfig({ ...config, [name]: false }));
});

test('check overview forwarding is opt-in GET with one bounded cutoff only', () => {
  const route = '/api/v1/assets/check-overview/counts';
  const url = route + '?cutoff=2024-02-29';
  assert.equal(access('GET', url), true);
  assert.equal(access('GET', url, false), false);
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE'])
    assert.equal(access(method, url), false);
  for (const invalid of [
    route,
    url + '&owner=other',
    url + '&cutoff=2024-02-29',
    url + '#fragment',
    route + '?cutoff=2024-02-29T00:00:00Z',
  ])
    assert.equal(access('GET', invalid), false);
});
