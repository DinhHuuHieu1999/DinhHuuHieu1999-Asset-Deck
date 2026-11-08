import assert from 'node:assert/strict';
import test from 'node:test';
import { allowed } from './client-https-proxy.mjs';

test('location overview requires location opt-in and read-only exact route', () => {
  const path = '/api/v1/assets/locations/overview';
  assert.equal(allowed('GET', path), false);
  assert.equal(allowed('GET', path, false, true, false, true), true);
  assert.equal(
    allowed('GET', path + '?owner=foreign', false, true, false, true),
    true,
  );
  for (const method of ['POST', 'PUT', 'DELETE']) {
    assert.equal(allowed(method, path, false, true, false, true), false);
  }
  for (const other of [path + '/extra', 'https://example.com' + path]) {
    assert.equal(allowed('GET', other, false, true, false, true), false);
  }
});
