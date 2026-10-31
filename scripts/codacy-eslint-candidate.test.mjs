import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import {
  buildCandidate,
  withNodeScriptScope,
} from './codacy-eslint-candidate.mjs';
const require = createRequire(process.env.CODACY_ESLINT_PACKAGE);
const { ESLint, Linter } = require('eslint');
const pairs = [];
const inventory = JSON.parse(
  readFileSync(new URL('./codacy-eslint-policy.json', import.meta.url), 'utf8'),
);
const config = buildCandidate(
  process.env.CODACY_ESLINT_PACKAGE,
  process.cwd(),
  pairs,
);
const eslint = new ESLint({
  cwd: process.cwd(),
  overrideConfig: config,
  overrideConfigFile: true,
});

test('all declared rules and exact options survive candidate construction', () => {
  const collected = new Map();
  // Before deliberate Node/TS overrides, every generated rule must be retained.
  for (const entry of config.slice(0, -2)) {
    for (const [rule, value] of Object.entries(entry.rules || {}))
      collected.set(rule, value);
  }
  assert.equal(collected.size, 299);
  for (const row of inventory.rules)
    assert.deepEqual(collected.get(row.ruleId), row.ruleValue, row.ruleId);
});
test('effective Node config preserves every non-Jest rule applicable to JS', async () => {
  for (const file of [
    'scripts/client-https-proxy.mjs',
    'scripts/client-https-proxy.test.mjs',
    'scripts/serial-fixture-cleanup.test.mjs',
  ]) {
    const effective = await eslint.calculateConfigForFile(file);
    assert.equal(effective.languageOptions.globals.process, false);
    for (const row of inventory.rules) {
      if (row.group === '@typescript-eslint') continue;
      const expected = row.group.startsWith('jest') ? 0 : 2;
      assert.equal(effective.rules[row.ruleId][0], expected, row.ruleId);
      if (expected === 2 && Array.isArray(row.ruleValue)) {
        assert.deepEqual(
          effective.rules[row.ruleId].slice(1, row.ruleValue.length),
          row.ruleValue.slice(1),
          row.ruleId,
        );
      }
    }
  }
});
test('backend config retains TS parser and Jest rules', async () => {
  const effective = await eslint.calculateConfigForFile(
    'backend/src/domains/assets/asset-serial-warning.spec.ts',
  );
  assert.equal(effective.rules['no-undef'][0], 0);
  assert.equal(effective.rules['jest/no-deprecated-functions'][0], 2);
  assert.equal(effective.languageOptions.parserOptions.projectService, true);
  for (const row of inventory.rules.filter(
    (r) => r.group === '@typescript-eslint',
  )) {
    assert.equal(effective.rules[row.ruleId][0], 2, row.ruleId);
  }
});

test('backend-root invocation retains all TS rules instead of silently losing coverage', async () => {
  const path = await import('node:path');
  const root = path.resolve('backend');
  const backendConfig = buildCandidate(
    process.env.CODACY_ESLINT_PACKAGE,
    root,
    pairs,
  );
  const backendESLint = new ESLint({
    cwd: root,
    overrideConfig: backendConfig,
    overrideConfigFile: true,
  });
  const effective = await backendESLint.calculateConfigForFile(
    'src/domains/assets/asset-serial-warning.spec.ts',
  );
  assert.equal(effective.languageOptions.parserOptions.tsconfigRootDir, root);
  for (const row of inventory.rules.filter(
    (r) => r.group === '@typescript-eslint',
  )) {
    assert.equal(effective.rules[row.ruleId][0], 2, row.ruleId);
  }
});

const globals = require('globals');
const jest = require('eslint-plugin-jest');
const security = require('eslint-plugin-security');
const base = [
  {
    files: ['**/*.mjs', '**/*.js'],
    plugins: { jest, security },
    settings: { jest: { version: 30 } },
    rules: {
      'no-undef': 'error',
      'jest/require-hook': 'error',
      'jest/no-disabled-tests': 'error',
      'security/detect-eval-with-expression': 'error',
    },
  },
];
const before = JSON.stringify(base[0].rules);
const scopeConfig = withNodeScriptScope(base, globals.node);
const verify = (code, filename = 'scripts/client-https-proxy.mjs') =>
  new Linter().verify(code, scopeConfig, { filename });

test('all three exact Node files accept Node globals', () => {
  for (const file of [
    'scripts/client-https-proxy.mjs',
    'scripts/client-https-proxy.test.mjs',
    'scripts/serial-fixture-cleanup.test.mjs',
  ]) {
    assert.deepEqual(
      verify(
        'Buffer.from("a"); process.cwd(); setTimeout(() => {}, 1); queueMicrotask(() => {});',
        file,
      ),
      [],
    );
  }
});
test('unknown identifiers remain errors', () => {
  assert.ok(
    verify('missingSyntheticIdentifier();').some(
      (x) => x.ruleId === 'no-undef',
    ),
  );
});
test('Node scope does not leak to other files', () => {
  assert.ok(
    verify('process.cwd();', 'scripts/unselected.mjs').some(
      (x) => x.ruleId === 'no-undef',
    ),
  );
});
test('node:test setup is not classified as Jest setup', () => {
  assert.deepEqual(verify('const value = Date.now(); void value;'), []);
});
test('Jest rules remain enabled outside the exact Node files', () => {
  assert.ok(
    verify('test.skip("synthetic", () => {});', 'backend/example.test.js').some(
      (x) => x.ruleId === 'jest/no-disabled-tests',
    ),
  );
});
test('security findings remain enabled inside Node scope', () => {
  assert.ok(
    verify('const input = "x"; eval(input);').some(
      (x) => x.ruleId === 'security/detect-eval-with-expression',
    ),
  );
});
test('base configuration is unchanged', () => {
  assert.equal(JSON.stringify(base[0].rules), before);
  assert.equal(scopeConfig[0], base[0]);
  assert.equal(scopeConfig[1].rules['no-undef'], undefined);
});

test('all installed Jest-family groups are scoped, while security rules are retained', () => {
  const rules = Object.fromEntries(
    [
      'jest/require-hook',
      'jest-formatting/padding-around-all',
      'jest-dom/prefer-checked',
      'jest-extended/prefer-to-be-array',
      'security/detect-object-injection',
      'security-node/detect-crlf',
    ].map((name) => [name, ['error', { synthetic: true }]]),
  );
  const original = JSON.stringify(rules);
  const result = withNodeScriptScope([{ rules }], globals.node);
  for (const name of Object.keys(rules)) {
    if (name.startsWith('jest')) assert.equal(result[1].rules[name], 'off');
    else assert.equal(result[1].rules[name], undefined);
  }
  assert.equal(JSON.stringify(rules), original);
  assert.equal(result[0].rules, rules);
});

test('unreviewed adapter package fails closed', () => {
  assert.throws(
    () =>
      buildCandidate(
        new URL('../backend/package.json', import.meta.url),
        process.cwd(),
      ),
    /Unsupported adapter/,
  );
});
