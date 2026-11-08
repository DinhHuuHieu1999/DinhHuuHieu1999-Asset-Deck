import { createHash } from 'node:crypto';
import { readFileSync, realpathSync, statSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { buildCandidate } from './codacy-eslint-candidate.mjs';

const self = fileURLToPath(import.meta.url);

/** Validate explicit source paths and hashes before loading the analyzer. */
export function validateSelection(rootPath, manifestPath) {
  const root = realpathSync(rootPath);
  if (statSync(manifestPath).size > 1024 * 1024)
    throw new Error('Manifest too large');
  const manifestBytes = readFileSync(manifestPath);
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  if (
    !Array.isArray(manifest.files) ||
    !manifest.files.length ||
    manifest.files.length > 100
  ) {
    throw new Error('Expected 1 to 100 explicit files');
  }
  const seen = new Set();
  for (const entry of manifest.files) {
    const name = entry?.path;
    if (
      typeof name !== 'string' ||
      !/^[a-f0-9]{64}$/.test(entry.sha256 ?? '') ||
      path.isAbsolute(name) ||
      /[\\:*?\[\]{}\x00-\x1f]/u.test(name) ||
      name.split('/').some((part) => !part || part === '.' || part === '..') ||
      /(^|\/)(\.git|\.local|\.codacy|node_modules|dist|build|\.next)(\/|$)/iu.test(
        name,
      ) ||
      /(^|\/)\.env/iu.test(name) ||
      !/\.(?:mjs|cjs|js|jsx|ts|tsx)$/u.test(name) ||
      seen.has(name.toLowerCase())
    ) {
      throw new Error('Unsafe or duplicate source entry');
    }
    seen.add(name.toLowerCase());
    const target = realpathSync(path.join(root, name));
    const relative = path.relative(root, target);
    if (
      !relative ||
      relative.startsWith('..') ||
      path.isAbsolute(relative) ||
      !statSync(target).isFile() ||
      statSync(target).size > 5 * 1024 * 1024 ||
      createHash('sha256').update(readFileSync(target)).digest('hex') !==
        entry.sha256
    ) {
      throw new Error('Source outside root, too large, or hash mismatch');
    }
  }
  return {
    root,
    files: manifest.files.map((entry) => entry.path),
    manifestHash: createHash('sha256').update(manifestBytes).digest('hex'),
  };
}

/** Classify results conservatively; execution success is not a security certification. */
export function summarize(results, expected) {
  if (!Array.isArray(results) || results.length !== expected.length)
    throw new Error('Incomplete analyzer output');
  const paths = new Set();
  let findings = 0;
  for (const result of results) {
    if (
      !expected.includes(result.filePath) ||
      paths.has(result.filePath) ||
      !Array.isArray(result.messages) ||
      result.fatalErrorCount !== 0 ||
      !Number.isInteger(result.errorCount) ||
      result.errorCount < 0 ||
      !Number.isInteger(result.warningCount) ||
      result.warningCount < 0 ||
      result.messages.some(
        (message) => !message.ruleId || ![1, 2].includes(message.severity),
      ) ||
      result.messages.filter((message) => message.severity === 2).length !==
        result.errorCount ||
      result.messages.filter((message) => message.severity === 1).length !==
        result.warningCount
    ) {
      throw new Error(
        'Malformed, ignored, fatal, or mismatched analyzer result',
      );
    }
    paths.add(result.filePath);
    findings += result.messages.length;
  }
  return {
    status: findings ? 'findings' : 'completed_no_findings',
    findings,
    filesAnalyzed: paths.size,
  };
}

/** Execute once in a bounded child process; never install, retry, or auto-fix. */
export async function runLocal(args, execute = execFile) {
  const [root, manifest, adapterPackage, timeoutText] = args;
  const timeout = Number(timeoutText);
  if (
    args.length !== 4 ||
    !path.isAbsolute(adapterPackage ?? '') ||
    !Number.isInteger(timeout) ||
    timeout < 1 ||
    timeout > 900
  ) {
    throw new Error(
      'Usage: node scripts/codacy-eslint-local.mjs ROOT MANIFEST ABS_ADAPTER_PACKAGE TIMEOUT_SECONDS(1-900)',
    );
  }
  const initial = validateSelection(root, manifest);
  return await new Promise((resolve, reject) => {
    execute(
      process.execPath,
      [
        self,
        '--worker',
        path.resolve(root),
        path.resolve(manifest),
        adapterPackage,
      ],
      {
        timeout: timeout * 1000,
        maxBuffer: 16 * 1024 * 1024,
        windowsHide: true,
        shell: false,
      },
      (error, stdout, stderr) => {
        if (error)
          return reject(new Error(`Analyzer incomplete: ${error.message}`));
        if (stderr.trim())
          return reject(new Error(`Analyzer diagnostic: ${stderr.trim()}`));
        try {
          const report = JSON.parse(stdout);
          const selection = validateSelection(root, manifest);
          if (initial.manifestHash !== selection.manifestHash)
            throw new Error('Manifest changed during analysis');
          const summary = summarize(
            report.results,
            selection.files.map((name) => path.join(selection.root, name)),
          );
          resolve({ ...report, summary });
        } catch (failure) {
          reject(failure);
        }
      },
    );
  });
}

async function main() {
  if (process.argv[2] === '--worker') {
    const [root, manifest, adapterPackage] = process.argv.slice(3);
    const selection = validateSelection(root, manifest);
    const config = buildCandidate(adapterPackage, selection.root);
    const require = createRequire(adapterPackage);
    const { ESLint } = require('eslint');
    const eslint = new ESLint({
      cwd: selection.root,
      overrideConfigFile: true,
      overrideConfig: config,
      fix: false,
      globInputPaths: false,
    });
    const results = await eslint.lintFiles(selection.files);
    validateSelection(root, manifest);
    const expected = selection.files.map((name) =>
      path.join(selection.root, name),
    );
    summarize(results, expected);
    process.stdout.write(JSON.stringify({ results }));
  } else {
    const report = await runLocal(process.argv.slice(2));
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    process.exitCode = report.summary.findings ? 1 : 0;
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === self) {
  main().catch((error) => {
    process.stderr.write(
      `${JSON.stringify({ status: 'incomplete', error: error.message })}\n`,
    );
    process.exitCode = 2;
  });
}
