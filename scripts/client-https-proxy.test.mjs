import test from "node:test";
import assert from "node:assert/strict";
import {
  allowed,
  parseProxyArgs,
  cleanHeaders,
  createProxy,
  createHandler,
  validateConfig,
} from "./client-https-proxy.mjs";
const config = { upstreamPort: 19001, fixtureId: "a".repeat(32) };
test("configuration refuses non-owned routing before TLS construction", () => {
  for (const upstreamPort of [0, 8180.5, 65536, "19001"])
    assert.throws(() => validateConfig({ ...config, upstreamPort }));
  for (const fixtureId of ["", "../secret", "a".repeat(31)])
    assert.throws(() => validateConfig({ ...config, fixtureId }));
  assert.throws(() => createProxy({}, { ...config, timeoutMs: 0 }));
});
test("route allowlist rejects arbitrary upstream and destructive methods", () => {
  assert.equal(allowed("GET", "/api/v1/assets?q=%25_"), true);
  assert.equal(allowed("POST", "/api/v1/auth/register"), true);
  for (const path of [
    "http://example.com/",
    "//example.com/",
    "/api/v1/assets/../auth",
    "/admin",
    "/api/v1/assets%2f",
  ])
    assert.equal(allowed("GET", path), false);
  assert.equal(allowed("DELETE", "/api/v1/assets"), false);
});
test("connection nominated headers removed without losing auth cookies", () => {
  assert.deepEqual(
    cleanHeaders({
      connection: "x-private",
      "x-private": "discard",
      host: "external",
      authorization: "synthetic",
      cookie: "synthetic",
      "x-csrf-token": "synthetic",
      "x-request-timestamp": "1",
    }),
    {
      authorization: "synthetic",
      cookie: "synthetic",
      "x-csrf-token": "synthetic",
      "x-request-timestamp": "1",
    },
  );
});

// Stream-only tests: no listener, TLS material, backend, subprocess or network.
import { EventEmitter } from "node:events";
import { Readable } from "node:stream";

async function simulate({
  method = "POST",
  url = "/api/v1/assets",
  chunks = [Buffer.from("{}")],
  status = 200,
  responseChunks = [Buffer.from("{}")],
  timeoutMs = 1000,
  hanging = false,
  importEnabled = false,
  recoveryRequestId,
  upstreamComplete = true,
  capabilities = {},
} = {}) {
  const req = hanging ? new Readable({ read() {} }) : Readable.from(chunks);
  Object.assign(req, {
    method,
    url,
    headers: {
      authorization: "synthetic",
      cookie: "csrf_token=synthetic",
      "x-csrf-token": "synthetic",
      "x-request-timestamp": "1",
      host: "untrusted",
    },
  });
  const res = new EventEmitter();
  res.headersSent = false;
  res.writableEnded = false;
  res.destroyed = false;
  res.writeHead = (code, headers) => {
    res.code = code;
    res.headers = headers;
    res.headersSent = true;
  };
  let flushed = false,
    destroyedBeforeFlush = false;
  const destroyRequest = req.destroy.bind(req);
  req.destroy = (...args) => {
    if (!flushed) destroyedBeforeFlush = true;
    return destroyRequest(...args);
  };
  res.end = (body) => {
    res.body = body;
    res.writableEnded = true;
    queueMicrotask(() => {
      flushed = true;
      res.emit("finish");
      res.emit("close");
    });
  };
  res.destroy = () => {
    res.destroyed = true;
    res.emit("close");
  };
  let calls = 0,
    options,
    sent;
  const transport = (opts, callback) => {
    calls++;
    options = opts;
    const outgoing = new EventEmitter();
    outgoing.destroy = () => {};
    outgoing.end = (body) => {
      sent = body;
      queueMicrotask(() => {
        const incoming = Readable.from(responseChunks);
        incoming.statusCode = status;
        incoming.complete = upstreamComplete;
        incoming.headers = {
          "content-type": "application/json",
          connection: "x-private",
          "x-private": "discard",
        };
        callback(incoming);
      });
    };
    return outgoing;
  };
  const finished = new Promise((resolve) => res.once("close", resolve));
  await createHandler(
    { ...config, timeoutMs, importEnabled, recoveryRequestId, ...capabilities },
    transport,
  )(req, res);
  await finished;
  return { res, calls, options, sent, destroyedBeforeFlush };
}

test("stream proxy forwards only to fixed loopback with exact body and auth headers", async () => {
  const { res, calls, options, sent } = await simulate();
  assert.equal(calls, 1);
  assert.equal(options.hostname, "127.0.0.1");
  assert.equal(options.port, config.upstreamPort);
  assert.equal(options.headers.authorization, "synthetic");
  assert.equal(options.headers.cookie, "csrf_token=synthetic");
  assert.equal(options.headers["x-csrf-token"], "synthetic");
  assert.equal(options.headers["x-request-timestamp"], "1");
  assert.equal(options.headers.host, undefined);
  assert.equal(sent.toString(), "{}");
  assert.equal(res.code, 200);
  assert.equal(res.headers["x-private"], undefined);
});
test("identity marker and denied routes never contact upstream", async () => {
  const marker = await simulate({
    method: "GET",
    url: `/__asset_desk_fixture/${config.fixtureId}`,
  });
  assert.equal(marker.calls, 0);
  assert.deepEqual(JSON.parse(marker.res.body), {
    fixtureId: config.fixtureId,
    syntheticOnly: true,
  });
  const denied = await simulate({ method: "DELETE" });
  assert.equal(denied.calls, 0);
  assert.equal(denied.res.code, 404);
});
test("oversized request is refused before contacting upstream", async () => {
  const result = await simulate({ chunks: [Buffer.alloc(1024 * 1024 + 1)] });
  assert.equal(result.calls, 0);
  assert.equal(result.res.code, 413);
});
test("oversized upstream response and redirect fail without exposing response", async () => {
  for (const options of [
    { responseChunks: [Buffer.alloc(1024 * 1024 + 1)] },
    { status: 302, responseChunks: [Buffer.from("private")] },
  ]) {
    const result = await simulate(options);
    assert.equal(result.calls, 1);
    assert.equal(result.res.code, 502);
    assert.equal(result.res.body.includes("private"), false);
  }
});
test("incomplete body hits total deadline without contacting upstream", async () => {
  const result = await simulate({ hanging: true, timeoutMs: 10 });
  assert.equal(result.calls, 0);
  assert.equal(result.res.code, 504);
});

import backendReadiness from "./client-https-backend.cjs";
test("backend readiness is written only after the exact server binds", () => {
  const expected = { fixtureId: config.fixtureId, port: 19002 };
  for (const address of [
    null,
    { address: "0.0.0.0", port: 19002 },
    { address: "127.0.0.1", port: 1 },
    { address: "127.0.0.1", port: 19002 },
  ]) {
    const server = new EventEmitter();
    server.address = () => address;
    const writes = [];
    backendReadiness.watch(server, expected, (...args) => writes.push(args));
    assert.equal(writes.length, 0);
    server.emit("listening");
    const matches = address?.address === "127.0.0.1" && address?.port === 19002;
    assert.equal(writes.length, matches ? 1 : 0);
    if (matches) {
      assert.deepEqual(JSON.parse(writes[0][1]), {
        fixtureId: config.fixtureId,
        pid: process.pid,
        port: 19002,
      });
      assert.equal(writes[0][2].flag, "wx");
    }
  }
});

test("inventory export is an exact GET-only fixture route", () => {
  assert.equal(allowed("GET", "/api/v1/assets/export"), true);
  assert.equal(
    allowed("GET", "/api/v1/assets/export?q=missing&owner=synthetic"),
    true,
  );
  for (const method of ["POST", "PUT", "PATCH", "DELETE"])
    assert.equal(allowed(method, "/api/v1/assets/export"), false);
  for (const path of [
    "/api/v1/assets/export/other",
    "/api/v1/assets/export/",
    "/api/v1/assets/%65xport",
    "/api/v1/assets/export/../auth",
  ])
    assert.equal(allowed("GET", path), false);
});

test("export forwarding preserves upstream 200, 401 and 422 without retry", async () => {
  const url = "/api/v1/assets/export?q=missing&owner=synthetic";
  for (const status of [200, 401, 422]) {
    const payload = Buffer.from(JSON.stringify({ synthetic: true, status }));
    const result = await simulate({
      method: "GET",
      url,
      chunks: [],
      status,
      responseChunks: [payload],
    });
    assert.equal(result.calls, 1);
    assert.equal(result.options.path, url);
    assert.equal(result.options.method, "GET");
    assert.equal(result.options.hostname, "127.0.0.1");
    assert.equal(result.options.headers.authorization, "synthetic");
    assert.equal(result.sent.length, 0);
    assert.equal(result.res.code, status);
    assert.deepEqual(result.res.body, payload);
    assert.equal(result.res.headers["cache-control"], "no-store");
  }
});

test("import routing is exact and opt-in, never a prefix wildcard", () => {
  assert.equal(allowed("POST", "/api/v1/assets/import"), false);
  assert.equal(allowed("POST", "/api/v1/assets/import", true), true);
  for (const value of ["true", 1, null]) {
    assert.throws(() => validateConfig({ ...config, importEnabled: value }));
    assert.equal(allowed("POST", "/api/v1/assets/import", value), false);
  }
  for (const path of [
    "/api/v1/assets/import/",
    "/api/v1/assets/import?owner=x",
    "/api/v1/assets/import/other",
    "/api/v1/assets%2fimport",
  ]) {
    assert.equal(allowed("POST", path, true), false);
  }
  for (const method of ["GET", "PUT", "DELETE"])
    assert.equal(allowed(method, "/api/v1/assets/import", true), false);
});

test("default import denial never invokes upstream", async () => {
  const result = await simulate({ url: "/api/v1/assets/import" });
  assert.equal(result.res.code, 404);
  assert.equal(result.calls, 0);
});

test("opt-in import preserves bytes, fixed upstream and existing body bound", async () => {
  const body = Buffer.from('{"requestId":"synthetic","records":[]}');
  const result = await simulate({
    url: "/api/v1/assets/import",
    importEnabled: true,
    chunks: [body],
  });
  assert.equal(result.res.code, 200);
  assert.equal(result.calls, 1);
  assert.deepEqual(result.sent, body);
  assert.equal(result.options.hostname, "127.0.0.1");
  assert.equal(result.options.port, config.upstreamPort);
  const oversized = await simulate({
    url: "/api/v1/assets/import",
    importEnabled: true,
    chunks: [Buffer.alloc(1024 * 1024 + 1)],
  });
  assert.equal(oversized.res.code, 413);
  assert.equal(oversized.calls, 0);
});

test("CLI import flag is explicit and malformed arguments fail before TLS", () => {
  const base = [
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
  ];
  assert.equal(parseProxyArgs(base).config.importEnabled, false);
  assert.equal(
    parseProxyArgs([...base, "--import-enabled"]).config.importEnabled,
    true,
  );
  for (const args of [
    [],
    base.slice(1),
    [...base, "true"],
    [...base, "--import-enabled", "extra"],
    [base[0], base[1], base[1], ...base.slice(3)],
  ])
    assert.throws(() => parseProxyArgs(args));
});

test("oversize response flushes before request destruction", async () => {
  const result = await simulate({
    url: "/api/v1/assets/import",
    importEnabled: true,
    chunks: [Buffer.alloc(1024 * 1024 + 1)],
  });
  assert.equal(result.res.code, 413);
  assert.equal(result.calls, 0);
  assert.equal(result.destroyedBeforeFlush, false);
});

const recoveryKey = "12345678-1234-4234-8234-123456789abc";
const recoveryBody = Buffer.from(
  JSON.stringify({ requestId: recoveryKey, records: [] }),
);
test("recovery fault never activates in default import profile", async () => {
  const result = await simulate({
    importEnabled: true,
    url: "/api/v1/assets/import",
    chunks: [recoveryBody],
  });
  assert.equal(result.res.code, 200);
  assert.equal(result.res.destroyed, false);
});
test("explicit recovery fault suppresses complete success without forwarding private receipt", async () => {
  const result = await simulate({
    importEnabled: true,
    recoveryRequestId: recoveryKey,
    url: "/api/v1/assets/import",
    chunks: [recoveryBody],
    responseChunks: [Buffer.from("private-receipt")],
  });
  assert.equal(result.calls, 1);
  assert.equal(result.res.destroyed, true);
  assert.equal(result.res.headersSent, false);
  assert.equal(result.res.body, undefined);
});
test("recovery fault does not suppress errors or incomplete upstream response", async () => {
  for (const extra of [{ status: 409 }, { upstreamComplete: false }]) {
    const result = await simulate({
      importEnabled: true,
      recoveryRequestId: recoveryKey,
      url: "/api/v1/assets/import",
      chunks: [recoveryBody],
      ...extra,
    });
    assert.equal(result.res.destroyed, false);
    assert.equal(result.res.code, extra.status ?? 502);
  }
});
test("recovery selector requires import capability before server construction", () => {
  assert.throws(() =>
    createProxy({}, { ...config, recoveryRequestId: recoveryKey }),
  );
  assert.throws(() =>
    createProxy(
      {},
      { ...config, importEnabled: true, recoveryRequestId: "bad" },
    ),
  );
});

test("overview allowlist adds only the exact read route", async () => {
  assert.equal(allowed("GET", "/api/v1/assets/overview"), true);
  for (const method of ["POST", "PUT", "PATCH", "DELETE"])
    assert.equal(allowed(method, "/api/v1/assets/overview"), false);
  for (const path of [
    "/api/v1/assets/overview/extra",
    "/api/v1/assets/Overview",
    "/api/v1/assets/%6fverview",
    "/api/v1/assets/overview/../import",
  ])
    assert.equal(allowed("GET", path), false);
  const result = await simulate({
    method: "GET",
    url: "/api/v1/assets/overview",
  });
  assert.equal(result.res.code, 200);
});

test("dates capability permits only exact opted-in UUID GET/PUT routes", () => {
  const route = "/api/v1/assets/11111111-1111-4111-8111-111111111111/dates";
  for (const method of ["GET", "PUT"]) {
    assert.equal(allowed(method, route), false);
    assert.equal(allowed(method, route, true), false);
    assert.equal(allowed(method, route, false, true), true);
    for (const invalid of [
      route + "?owner=x",
      route + "/",
      route.replace("/dates", "/dates/other"),
      "/api/v1/assets/no-id/dates",
    ])
      assert.equal(allowed(method, invalid, false, true), false);
  }
  for (const method of ["POST", "DELETE", "PATCH"])
    assert.equal(allowed(method, route, false, true), false);
  assert.throws(() => validateConfig({ ...config, datesEnabled: "true" }));
  const parsed = parseProxyArgs([
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
    "--dates-enabled",
  ]);
  assert.equal(parsed.config.datesEnabled, true);
  assert.equal(parsed.config.importEnabled, false);
});

test("export v2 permits only the exact opted-in dates GET route", () => {
  const path = "/api/v1/assets/export/v2";
  assert.equal(allowed("GET", path), false);
  assert.equal(allowed("GET", path, true), false);
  assert.equal(allowed("GET", path, false, true), true);
  for (const method of ["POST", "PUT", "PATCH", "DELETE"])
    assert.equal(allowed(method, path, false, true), false);
  for (const invalid of [
    path + "?owner=x",
    path + "/",
    path + "/other",
    path.replace("/v2", "/%76%32"),
  ])
    assert.equal(allowed("GET", invalid, false, true), false);
});

test("warranty route is exact GET-only and dates opt-in; queries reach backend validation", () => {
  const path = "/api/v1/assets/warranty";
  for (const query of [
    "",
    "?warranty=expired&asOf=2026-10-26",
    "?ownerId=synthetic",
  ]) {
    assert.equal(allowed("GET", path + query), false);
    assert.equal(allowed("GET", path + query, true), false);
    assert.equal(allowed("GET", path + query, false, true), true);
  }
  for (const method of ["POST", "PUT", "PATCH", "DELETE"])
    assert.equal(allowed(method, path, false, true), false);
  for (const invalid of [
    path + "/",
    path + "/other",
    path.replace("warranty", "%77arranty"),
  ])
    assert.equal(allowed("GET", invalid, false, true), false);
});

test("warranty overview is GET-only and requires explicit dates capability", () => {
  for (const path of [
    "/api/v1/assets/warranty/overview",
    "/api/v1/assets/warranty/overview?asOf=2026-10-26",
  ]) {
    assert.equal(allowed("GET", path, false, true), true);
    assert.equal(allowed("GET", path), false);
    assert.equal(allowed("GET", path, true, false), false);
    for (const method of ["POST", "PUT", "DELETE", "PATCH"])
      assert.equal(allowed(method, path, false, true), false);
  }
  assert.equal(
    allowed("GET", "/api/v1/assets/warranty/overview/extra", false, true),
    false,
  );
});

test("v2 requires all capabilities and an exact POST route", () => {
  const route = "/api/v1/assets/import/v2";
  for (const flags of [
    [false, false, false],
    [true, true, false],
    [true, false, true],
    [false, true, true],
  ])
    assert.equal(allowed("POST", route, ...flags), false);
  assert.equal(allowed("POST", route, true, true, true), true);
  for (const routeAlias of [route + "/", route + "?x=1", route.toUpperCase()])
    assert.equal(allowed("POST", routeAlias, true, true, true), false);
  assert.equal(allowed("GET", route, true, true, true), false);
});
test("v2 CLI selects fixed prerequisites without widening legacy profiles", () => {
  const args = [
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
  ];
  const selected = parseProxyArgs([...args, "--import-v2-enabled"]).config;
  assert.equal(selected.importEnabled, true);
  assert.equal(selected.datesEnabled, true);
  assert.equal(selected.importV2Enabled, true);
  assert.equal(
    parseProxyArgs([...args, "--import-enabled"]).config.importV2Enabled,
    false,
  );
  for (const flags of [{}, { importEnabled: true }, { datesEnabled: true }])
    assert.throws(() =>
      validateConfig({ ...config, ...flags, importV2Enabled: true }),
    );
});

test("location routes are opt-in and cannot enable import", () => {
  const id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const path = `/api/v1/assets/${id}/location`;
  assert.equal(allowed("GET", path), false);
  assert.equal(allowed("PUT", path, false, true, false, true), true);
  assert.equal(
    allowed(
      "GET",
      "/api/v1/assets/locations/inventory?location=%25_",
      false,
      true,
      false,
      true,
    ),
    true,
  );
  assert.equal(allowed("DELETE", path, false, true, false, true), false);
  assert.equal(
    allowed(
      "GET",
      "/api/v1/assets/not-uuid/location",
      false,
      true,
      false,
      true,
    ),
    false,
  );
  assert.equal(
    allowed("POST", "/api/v1/assets/import", false, true, false, true),
    false,
  );
  assert.throws(() =>
    validateConfig({ ...config, locationEnabled: "true", datesEnabled: true }),
  );
  assert.throws(() => validateConfig({ ...config, locationEnabled: true }));
  assert.throws(() =>
    validateConfig({
      ...config,
      locationEnabled: true,
      datesEnabled: true,
      importEnabled: true,
    }),
  );
  const parsed = parseProxyArgs([
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
    "--location-enabled",
  ]);
  assert.equal(parsed.config.locationEnabled, true);
  assert.equal(parsed.config.datesEnabled, true);
  assert.equal(parsed.config.importEnabled, false);
});

test("v3 CLI requires fixed capabilities and leaves older profiles unchanged", () => {
  const args = [
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
  ];
  const selected = parseProxyArgs([...args, "--import-v3-enabled"]).config;
  for (const key of [
    "importEnabled",
    "datesEnabled",
    "locationEnabled",
    "exportV3Enabled",
    "importV3Enabled",
  ]) {
    assert.equal(selected[key], true);
    if (key !== "importV3Enabled")
      assert.throws(() => validateConfig({ ...selected, [key]: false }));
  }
  assert.equal(selected.importV2Enabled, false);
  assert.throws(() => validateConfig({ ...selected, importV2Enabled: true }));
  assert.equal(selected.recoveryRequestId, undefined);
  for (const flag of [
    "--import-enabled",
    "--import-v2-enabled",
    "--location-enabled",
    "--export-v3-enabled",
  ])
    assert.equal(parseProxyArgs([...args, flag]).config.importV3Enabled, false);
});

test("v3 import is exact POST-only and opt-in, never enabled by export alone", () => {
  const route = "/api/v1/assets/import/v3";
  const flags = [true, true, false, true, true, true];
  assert.equal(allowed("POST", route, ...flags), true);
  assert.equal(allowed("POST", route, false, true, false, true, true), false);
  for (const alias of [
    route + "/",
    route + "?x=1",
    route.toUpperCase(),
    "/api/v1/assets/import/v30",
  ])
    assert.equal(allowed("POST", alias, ...flags), false);
  assert.equal(allowed("GET", route, ...flags), false);
  assert.equal(allowed("POST", "/api/v1/assets/import/v2", ...flags), false);
});

test("v3 stream forwarding retains exact bytes and refuses unselected route", async () => {
  const capabilities = parseProxyArgs([
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
    "--import-v3-enabled",
  ]).config;
  const bytes = Buffer.from(
    '{"requestId":"synthetic","records":[{"location":"Room %_1"}]}',
  );
  const result = await simulate({
    url: "/api/v1/assets/import/v3",
    chunks: [bytes],
    capabilities,
  });
  assert.equal(result.calls, 1);
  assert.equal(result.options.hostname, "127.0.0.1");
  assert.equal(result.options.path, "/api/v1/assets/import/v3");
  assert.equal(result.sent.toString(), bytes.toString());
  const denied = await simulate({ url: "/api/v1/assets/import/v3" });
  assert.equal(denied.calls, 0);
  assert.equal(denied.res.code, 404);
});

test("explicit v3 recovery suppresses only a complete successful selected reply", async () => {
  const capabilities = parseProxyArgs([
    "--synthetic-only",
    "19001",
    "19002",
    "a".repeat(32),
    "cert",
    "key",
    "--import-v3-enabled",
  ]).config;
  const requestId = "12345678-1234-4234-8234-123456789abc";
  const chunks = [Buffer.from(JSON.stringify({ requestId, records: [] }))];
  const selected = {
    url: "/api/v1/assets/import/v3",
    chunks,
    capabilities,
    recoveryRequestId: requestId,
  };
  const success = await simulate({
    ...selected,
    responseChunks: [Buffer.from("private-receipt")],
  });
  assert.equal(success.calls, 1);
  assert.equal(success.res.destroyed, true);
  assert.equal(success.res.body, undefined);
  const conflict = await simulate({ ...selected, status: 409 });
  assert.equal(conflict.res.code, 409);
  assert.equal(conflict.res.destroyed, false);
  const incomplete = await simulate({ ...selected, upstreamComplete: false });
  assert.equal(incomplete.res.code, 502);
});
