import { createRequire } from 'node:module';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

/** Build a opt-in configuration using an explicit, already installed adapter package. */
export function buildCandidate(adapterPackage, repositoryRoot) {
  const require = createRequire(adapterPackage);
  const adapter = JSON.parse(readFileSync(adapterPackage, 'utf8'));
  if (
    adapter.name !== '@codacy/tools-eslint-9' ||
    adapter.version !== '0.16.0'
  ) {
    throw new Error(
      'Unsupported adapter; review rule compatibility before use',
    );
  }
  const policy = JSON.parse(
    readFileSync(
      new URL('./codacy-eslint-policy.json', import.meta.url),
      'utf8',
    ),
  );
  const inventory = { rules: policy.rules };
  const extensionPairs = policy.extensionPairs;
  const packages = {
    jest: 'eslint-plugin-jest',
    'jest-dom': 'eslint-plugin-jest-dom',
    'jest-extended': 'eslint-plugin-jest-extended',
    security: 'eslint-plugin-security',
    'security-node': 'eslint-plugin-security-node',
    xss: 'eslint-plugin-xss',
  };
  const nestedBackend = existsSync(
    path.join(repositoryRoot, 'backend', 'tsconfig.json'),
  );
  const tsFiles = nestedBackend
    ? ['backend/**/*.ts', 'backend/**/*.tsx']
    : ['**/*.ts', '**/*.tsx'];
  const tsRoot = nestedBackend
    ? path.join(repositoryRoot, 'backend')
    : repositoryRoot;
  const jestRequire = createRequire(path.join(tsRoot, 'package.json'));
  const jestVersion = JSON.parse(
    readFileSync(jestRequire.resolve('jest/package.json'), 'utf8'),
  ).version;
  const jestMajor = Number(jestVersion.split('.')[0]);
  if (jestMajor !== 30)
    throw new Error('Unreviewed Jest version; expected major 30');
  const configs = [];
  const common = [
    '**/*.js',
    '**/*.jsx',
    '**/*.mjs',
    '**/*.cjs',
    '**/*.ts',
    '**/*.tsx',
  ];
  const groups = new Map();
  for (const row of inventory.rules) {
    if (!row.defaultsResolved)
      throw new Error(`Unresolved defaults: ${row.ruleId}`);
    if (!groups.has(row.group)) groups.set(row.group, {});
    groups.get(row.group)[row.ruleId] = row.ruleValue;
  }
  configs.push({
    files: ['**/*.jsx', '**/*.tsx'],
    languageOptions: { parserOptions: { ecmaFeatures: { jsx: true } } },
  });
  configs.push({ files: common, rules: groups.get('core') });
  for (const [group, rules] of groups) {
    if (group === 'core') continue;
    if (group === '@typescript-eslint') {
      const ts = require('typescript-eslint');
      configs.push({
        files: tsFiles,
        plugins: { [group]: ts.plugin },
        rules,
        languageOptions: {
          parser: ts.parser,
          parserOptions: {
            projectService: true,
            tsconfigRootDir: tsRoot,
          },
        },
      });
    } else {
      const mod = require(packages[group]);
      const entry = {
        files: common,
        plugins: { [group]: mod.default || mod },
        rules,
      };
      if (group.startsWith('jest'))
        entry.settings = { jest: { version: jestMajor } };
      configs.push(entry);
    }
  }
  const overrides = { 'no-undef': 'off' };
  for (const [core, ts] of extensionPairs) {
    if (
      groups.get('core')[core] !== undefined &&
      groups.get('@typescript-eslint')[ts] !== undefined
    )
      overrides[core] = 'off';
  }
  configs.push({ files: tsFiles, rules: overrides });
  return withNodeScriptScope(configs, require('globals').node);
}

const nodeFiles = [
  'scripts/client-https-proxy.mjs',
  'scripts/client-https-proxy.test.mjs',
  'scripts/serial-fixture-cleanup.test.mjs',
];

/** Add exact Node-file overrides without mutating the supplied flat configuration. */
export function withNodeScriptScope(baseConfig, nodeGlobals) {
  const disabledFrameworkRules = {};
  for (const entry of baseConfig) {
    for (const name of Object.keys(entry.rules || {})) {
      if (
        ['jest', 'jest-formatting', 'jest-dom', 'jest-extended'].some(
          (prefix) => name.startsWith(`${prefix}/`),
        )
      ) {
        disabledFrameworkRules[name] = 'off';
      }
    }
  }
  return [
    ...baseConfig,
    {
      name: 'asset-desk/exact-node-script-scope',
      files: [...nodeFiles],
      languageOptions: { globals: { ...nodeGlobals } },
      rules: disabledFrameworkRules,
    },
  ];
}
