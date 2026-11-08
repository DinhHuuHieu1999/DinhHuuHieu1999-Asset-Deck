import test from 'node:test';
import assert from 'node:assert/strict';
import { allowed, parseProxyArgs } from './client-https-proxy.mjs';

test('saved-filter routes require explicit profile and exact method/path', () => {
  const args = ['--synthetic-only','29441','29443','a'.repeat(32),'cert','key','--saved-filters-enabled'];
  const {config} = parseProxyArgs(args);
  assert.equal(config.savedFiltersEnabled,true);
  assert.equal(config.checkEnabled,true);
  const path='/api/v1/inventory-saved-filters';
  const id='11111111-1111-4111-8111-111111111111';
  const permits=(method,url,enabled=true) => allowed(method,url,false,true,false,true,false,false,false,true,false,false,false,enabled);
  for(const method of ['GET','POST']) {
    assert.equal(permits(method,path),true);
    assert.equal(permits(method,path,false),false);
  }
  for(const method of ['PUT','DELETE']) assert.equal(permits(method,`${path}/${id}`),true);
  for(const [method,url] of [['DELETE',path],['GET',`${path}/${id}`],['POST',`${path}?owner=other`],['PUT',`${path}/not-id`]]) {
    assert.equal(permits(method,url),false);
  }
});
