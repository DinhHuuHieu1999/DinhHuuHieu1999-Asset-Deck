import assert from "node:assert/strict";
import test from "node:test";
import {
  allowed,
  parseProxyArgs,
  validateConfig,
} from "./client-https-proxy.mjs";

test("v3 proxy routing is separate, read-only and explicitly enabled", () => {
  const args = [
    "--synthetic-only",
    "29542",
    "29543",
    "a".repeat(32),
    "cert",
    "key",
  ];
  const old = parseProxyArgs(args).config;
  assert.equal(old.exportV3Enabled, false);
  const config = parseProxyArgs([...args, "--export-v3-enabled"]).config;
  assert.equal(config.exportV3Enabled, true);
  assert.equal(config.locationEnabled, true);
  assert.equal(config.datesEnabled, true);
  assert.equal(config.importEnabled, false);
  assert.equal(allowed("GET", "/api/v1/assets/export/v3"), false);
  assert.equal(
    allowed("GET", "/api/v1/assets/export/v3", false, true, false, true, true),
    true,
  );
  assert.equal(
    allowed("POST", "/api/v1/assets/export/v3", false, true, false, true, true),
    false,
  );
  assert.equal(
    allowed("POST", "/api/v1/assets/import/v2", false, true, false, true, true),
    false,
  );
  for (const change of [
    { datesEnabled: false },
    { locationEnabled: false },
    { exportV3Enabled: "true" },
    { importEnabled: true },
  ]) {
    assert.throws(() => validateConfig({ ...config, ...change }));
  }
});
