import test from "node:test";
import assert from "node:assert/strict";
import { createRecoveryFault } from "./import-recovery-fault.mjs";
const requestId = "12345678-1234-4234-8234-123456789abc";
const config = { syntheticOnly: true, importEnabled: true, requestId };
const body = Buffer.from(JSON.stringify({ requestId, records: [] }));

test("fault requires explicit synthetic import opt-in and canonical key", () => {
  for (const bad of [
    { syntheticOnly: false },
    { importEnabled: false },
    { requestId: "../anything" },
    { requestId: requestId.toUpperCase() },
  ]) {
    assert.throws(() => createRecoveryFault({ ...config, ...bad }));
  }
});
test("only exact import POST with selected key can claim once", () => {
  const fault = createRecoveryFault(config);
  for (const [method, path, bytes] of [
    ["GET", "/api/v1/assets/import", body],
    ["POST", "/api/v1/assets/import?q=1", body],
    ["POST", "/api/v1/assets", body],
    ["POST", "/api/v1/assets/import", Buffer.from("{}")],
    ["POST", "/api/v1/assets/import", Buffer.from("{")],
    ["POST", "/api/v1/assets/import", Buffer.from([0xff])],
    ["POST", "/api/v1/assets/import", Buffer.alloc(1024 * 1024 + 1)],
  ])
    assert.equal(fault.claim(method, path, bytes), false);
  assert.equal(fault.claim("POST", "/api/v1/assets/import", body), true);
  assert.equal(fault.claim("POST", "/api/v1/assets/import", body), false);
});
test("disconnect is allowed only after complete upstream success", () => {
  for (const [status, complete] of [
    [200, false],
    [201, undefined],
    [409, true],
    [500, true],
    [302, true],
    ["200", true],
  ]) {
    const fault = createRecoveryFault(config);
    const selected = fault.claim("POST", "/api/v1/assets/import", body);
    assert.equal(fault.complete(selected, status, complete), false);
    assert.deepEqual(fault.status(), { claimed: true, suppressed: false });
  }
});
test("successful fault fires once; unrelated responses cannot consume it", () => {
  const fault = createRecoveryFault(config);
  assert.equal(fault.complete(true, 200, true), false);
  const selected = fault.claim("POST", "/api/v1/assets/import", body);
  assert.equal(fault.complete(false, 200, true), false);
  assert.equal(fault.complete(selected, 201, true), true);
  assert.equal(fault.complete(selected, 201, true), false);
  assert.deepEqual(fault.status(), { claimed: true, suppressed: true });
});

import { parseRecoveryProxyArgs } from "./import-recovery-proxy-cli.mjs";
test("dedicated recovery CLI rejects implicit or malformed fault selection before TLS", () => {
  const args = [
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
    "--import-enabled",
    "--lose-import-ack",
    requestId,
  ];
  assert.equal(
    parseRecoveryProxyArgs(args).config.recoveryRequestId,
    requestId,
  );
  for (const bad of [
    args.slice(0, 7),
    [...args, "extra"],
    args.map((x, i) => (i === 6 ? "implicit" : x)),
    args.map((x, i) => (i === 8 ? "bad" : x)),
  ])
    assert.throws(() => parseRecoveryProxyArgs(bad));
});
