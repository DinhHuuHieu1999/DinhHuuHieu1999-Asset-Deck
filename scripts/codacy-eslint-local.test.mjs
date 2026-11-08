import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import {
  validateSelection,
  summarize,
  runLocal,
} from './codacy-eslint-local.mjs';

function fixture() {
  const root = mkdtempSync(path.join(tmpdir(), 'eslint-local-contract-'));
  writeFileSync(path.join(root, 'source.mjs'), 'export const value = 1;');
  const files = [
    {
      path: 'source.mjs',
      sha256: createHash('sha256')
        .update('export const value = 1;')
        .digest('hex'),
    },
  ];
  const manifest = path.join(root, 'manifest.json');
  writeFileSync(manifest, JSON.stringify({ files }));
  return { root, manifest, files };
}
function result(filePath) {
  return {
    filePath,
    messages: [],
    errorCount: 0,
    warningCount: 0,
    fatalErrorCount: 0,
  };
}
test('explicit hashes validate and changed bytes fail', () => {
  const f = fixture();
  assert.deepEqual(validateSelection(f.root, f.manifest).files, ['source.mjs']);
  writeFileSync(path.join(f.root, 'source.mjs'), 'changed');
  assert.throws(() => validateSelection(f.root, f.manifest), /hash mismatch/u);
});
test('unsafe, glob, duplicate and empty selections fail', () => {
  const f = fixture();
  for (const files of [
    [],
    [f.files[0], f.files[0]],
    [{ ...f.files[0], path: '../source.mjs' }],
    [{ ...f.files[0], path: '*.mjs' }],
    [{ ...f.files[0], path: '.local/source.mjs' }],
  ]) {
    writeFileSync(f.manifest, JSON.stringify({ files }));
    assert.throws(() => validateSelection(f.root, f.manifest));
  }
});
test('findings are not a passing exit status', () => {
  const r = result('/source');
  r.messages = [{ ruleId: 'security/example', severity: 2 }];
  r.errorCount = 1;
  assert.deepEqual(summarize([r], ['/source']), {
    status: 'findings',
    findings: 1,
    filesAnalyzed: 1,
  });
});
test('missing, malformed, ignored and inconsistent results fail closed', () => {
  for (const results of [
    [],
    null,
    [result('/other')],
    [{ ...result('/source'), warningCount: 1 }],
    [{ ...result('/source'), fatalErrorCount: 1 }],
    [{ ...result('/source'), messages: [{ severity: 1 }], warningCount: 1 }],
  ]) {
    assert.throws(() => summarize(results, ['/source']));
  }
});
test('single bounded invocation uses no shell; returns validated output', async () => {
  const f = fixture();
  let calls = 0;
  const output = await runLocal(
    [f.root, f.manifest, path.join(f.root, 'package.json'), '120'],
    (exe, args, options, callback) => {
      calls++;
      assert.equal(exe, process.execPath);
      assert.equal(args[1], '--worker');
      assert.equal(options.timeout, 120000);
      assert.equal(options.shell, false);
      assert.equal(options.windowsHide, true);
      callback(
        null,
        JSON.stringify({ results: [result(path.join(f.root, 'source.mjs'))] }),
        '',
      );
    },
  );
  assert.equal(calls, 1);
  assert.equal(output.summary.status, 'completed_no_findings');
});
test('timeout, diagnostics and invalid output reject without retry', async () => {
  const f = fixture();
  for (const response of [
    [new Error('timeout'), '', ''],
    [null, '{}', 'warning'],
    [null, 'invalid', ''],
    [null, '{"results":[]}', ''],
  ]) {
    let calls = 0;
    await assert.rejects(
      runLocal(
        [f.root, f.manifest, path.join(f.root, 'package.json'), '1'],
        (_exe, _args, _options, callback) => {
          calls++;
          callback(...response);
        },
      ),
    );
    assert.equal(calls, 1);
  }
});
test('invalid timeout and changed source prevent analyzer success', async () => {
  const f = fixture();
  await assert.rejects(
    runLocal([f.root, f.manifest, path.join(f.root, 'package.json'), '901']),
  );
  await assert.rejects(
    runLocal(
      [f.root, f.manifest, path.join(f.root, 'package.json'), '1'],
      (_exe, _args, _options, callback) => {
        writeFileSync(path.join(f.root, 'source.mjs'), 'changed');
        callback(
          null,
          JSON.stringify({
            results: [result(path.join(f.root, 'source.mjs'))],
          }),
          '',
        );
      },
    ),
    /hash mismatch/u,
  );
});

test('manifest replacement during execution is incomplete even with valid source hashes', async () => {
  const f = fixture();
  await assert.rejects(
    runLocal(
      [f.root, f.manifest, path.join(f.root, 'package.json'), '1'],
      (_exe, _args, _options, callback) => {
        writeFileSync(
          f.manifest,
          JSON.stringify({ files: f.files, changed: true }),
        );
        callback(
          null,
          JSON.stringify({
            results: [result(path.join(f.root, 'source.mjs'))],
          }),
          '',
        );
      },
    ),
    /Manifest changed/u,
  );
});
test('duplicate analyzer files cannot stand in for missing files', () => {
  assert.throws(
    () => summarize([result('/a'), result('/a')], ['/a', '/b']),
    /mismatched/u,
  );
});
test('oversized source and manifest fail before analysis', () => {
  const f = fixture();
  writeFileSync(
    path.join(f.root, 'source.mjs'),
    Buffer.alloc(5 * 1024 * 1024 + 1),
  );
  assert.throws(() => validateSelection(f.root, f.manifest), /too large/u);
  writeFileSync(f.manifest, Buffer.alloc(1024 * 1024 + 1));
  assert.throws(
    () => validateSelection(f.root, f.manifest),
    /Manifest too large/u,
  );
});
