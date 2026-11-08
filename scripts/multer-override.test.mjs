import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const backend = join(dirname(fileURLToPath(import.meta.url)), '../backend');
const config = readFileSync(join(backend, 'pnpm-workspace.yaml'), 'utf8');
const lock = readFileSync(join(backend, 'pnpm-lock.yaml'), 'utf8');
const manifest = JSON.parse(
  readFileSync(join(backend, 'package.json'), 'utf8'),
);

test('override targets only the reviewed NestJS parent and exact Multer patch', () => {
  assert.match(
    config,
    /overrides:\s*['"]@nestjs\/platform-express@12\.0\.3>multer['"]: ['"]2\.5\.0['"]/u,
  );
  assert.equal(manifest.dependencies['@nestjs/platform-express'], '12.0.3');
  assert.equal(manifest.dependencies.multer, undefined);
  assert.equal(manifest.pnpm, undefined);
});

test('lockfile retains the scoped override and contains no vulnerable Multer', () => {
  assert.match(lock, /'@nestjs\/platform-express@12\.0\.3>multer': 2\.5\.0/u);
  assert.match(lock, /multer@2\.5\.0:/u);
  assert.match(lock, /multer: 2\.5\.0/u);
  assert.doesNotMatch(lock, /multer(?:@|: )2\.4\.0/u);
});
