import https from "node:https";
import http from "node:http";
import { createRecoveryFault } from "./import-recovery-fault.mjs";

const limit = 1024 * 1024;
const hop = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
]);

/** Validate fixed fixture routing before creating a server or reading TLS files. */
export function validateConfig({
  upstreamPort,
  fixtureId,
  timeoutMs = 15000,
  importEnabled = false,
  datesEnabled = false,
  importV2Enabled = false,
  locationEnabled = false,
  exportV3Enabled = false,
  importV3Enabled = false,
  selectionExportV2Enabled = false,
  selectionExportEnabled = false,
  checkEnabled = false,
  exportV4Enabled = false,
  recoveryRequestId,
}) {
  if (
    typeof importEnabled !== "boolean" ||
    typeof datesEnabled !== "boolean" ||
    typeof importV2Enabled !== "boolean" ||
    typeof locationEnabled !== "boolean" ||
    typeof exportV3Enabled !== "boolean" ||
    typeof exportV4Enabled !== "boolean" ||
    (exportV4Enabled &&
      (!checkEnabled ||
        !exportV3Enabled ||
        !datesEnabled ||
        !locationEnabled ||
        importEnabled ||
        importV2Enabled ||
        importV3Enabled ||
        selectionExportEnabled ||
        selectionExportV2Enabled)) ||
    typeof checkEnabled !== "boolean" ||
    (checkEnabled &&
      (!datesEnabled ||
        !locationEnabled ||
        importEnabled ||
        importV2Enabled ||
        importV3Enabled ||
        (!selectionExportV2Enabled &&
          !exportV4Enabled &&
          (exportV3Enabled || selectionExportEnabled)))) ||
    typeof selectionExportV2Enabled !== "boolean" ||
    (selectionExportV2Enabled && (!selectionExportEnabled || !checkEnabled)) ||
    typeof selectionExportEnabled !== "boolean" ||
    (selectionExportEnabled &&
      (!exportV3Enabled ||
        !locationEnabled ||
        !datesEnabled ||
        importEnabled ||
        importV2Enabled ||
        importV3Enabled)) ||
    typeof importV3Enabled !== "boolean" ||
    (importV3Enabled &&
      (!importEnabled ||
        !datesEnabled ||
        !locationEnabled ||
        !exportV3Enabled ||
        importV2Enabled)) ||
    (exportV3Enabled &&
      !importV3Enabled &&
      (!locationEnabled ||
        !datesEnabled ||
        importEnabled ||
        importV2Enabled)) ||
    (locationEnabled &&
      (!datesEnabled ||
        (!importV3Enabled && importEnabled) ||
        importV2Enabled)) ||
    (importV2Enabled && (!importEnabled || !datesEnabled)) ||
    !Number.isInteger(upstreamPort) ||
    upstreamPort < 1024 ||
    upstreamPort > 65535 ||
    !/^[a-f0-9]{32}$/.test(fixtureId) ||
    !Number.isInteger(timeoutMs) ||
    timeoutMs < 1 ||
    timeoutMs > 30000
  ) {
    throw new Error("Invalid fixture configuration");
  }
  if (recoveryRequestId !== undefined) {
    createRecoveryFault({
      syntheticOnly: true,
      importEnabled,
      requestId: recoveryRequestId,
      schemaVersion: importV3Enabled ? 3 : importV2Enabled ? 2 : 1,
    });
  }
}

/** Parse the fixed fixture CLI; optional import capability must be explicit. */
export function parseProxyArgs(args) {
  if (
    !Array.isArray(args) ||
    ![6, 7].includes(args.length) ||
    args[0] !== "--synthetic-only" ||
    (args.length === 7 &&
      ![
        "--import-enabled",
        "--dates-enabled",
        "--import-v2-enabled",
        "--location-enabled",
        "--export-v3-enabled",
        "--import-v3-enabled",
        "--selection-export-v2-enabled",
        "--selection-export-enabled",
        "--check-enabled",
        "--export-v4-enabled",
      ].includes(args[6]))
  )
    throw new Error("Explicit fixture opt-in required");
  const [, upstream, listen, fixtureId, cert, key] = args;
  const config = {
    upstreamPort: Number(upstream),
    fixtureId,
    importEnabled: [
      "--import-enabled",
      "--import-v2-enabled",
      "--import-v3-enabled",
    ].includes(args[6]),
    datesEnabled: [
      "--export-v4-enabled",
      "--check-enabled",
      "--selection-export-v2-enabled",
      "--selection-export-enabled",
      "--import-v3-enabled",
      "--dates-enabled",
      "--import-v2-enabled",
      "--location-enabled",
      "--export-v3-enabled",
    ].includes(args[6]),
    importV2Enabled: args[6] === "--import-v2-enabled",
    locationEnabled: [
      "--export-v4-enabled",
      "--check-enabled",
      "--selection-export-v2-enabled",
      "--selection-export-enabled",
      "--location-enabled",
      "--export-v3-enabled",
      "--import-v3-enabled",
    ].includes(args[6]),
    exportV3Enabled: [
      "--export-v4-enabled",
      "--selection-export-v2-enabled",
      "--selection-export-enabled",
      "--export-v3-enabled",
      "--import-v3-enabled",
    ].includes(args[6]),
    importV3Enabled: args[6] === "--import-v3-enabled",
    selectionExportV2Enabled: args[6] === "--selection-export-v2-enabled",
    selectionExportEnabled: [
      "--selection-export-v2-enabled",
      "--selection-export-enabled",
    ].includes(args[6]),
    exportV4Enabled: args[6] === "--export-v4-enabled",
    checkEnabled: [
      "--export-v4-enabled",
      "--check-enabled",
      "--selection-export-v2-enabled",
    ].includes(args[6]),
  };
  validateConfig(config);
  const port = Number(listen);
  if (
    !Number.isInteger(port) ||
    port < 1024 ||
    port > 65535 ||
    port === config.upstreamPort ||
    !cert ||
    !key
  )
    throw new Error("Invalid fixture arguments");
  return { config, port, cert, key };
}

/** Allow only the API operations exercised by the synthetic client. */
export function allowed(
  method,
  raw,
  importEnabled = false,
  datesEnabled = false,
  importV2Enabled = false,
  locationEnabled = false,
  exportV3Enabled = false,
  importV3Enabled = false,
  selectionExportEnabled = false,
  checkEnabled = false,
  selectionExportV2Enabled = false,
  exportV4Enabled = false,
) {
  if (typeof raw !== "string" || !raw.startsWith("/") || raw.startsWith("//"))
    return false;
  if (
    /^\/api\/v1\/assets\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/check-date$/i.test(
      raw,
    )
  )
    return checkEnabled === true && ["GET", "PUT"].includes(method);
  if (raw.split("?")[0] === "/api/v1/assets/check-overview/counts")
    return (
      checkEnabled === true &&
      method === "GET" &&
      /^\/api\/v1\/assets\/check-overview\/counts\?cutoff=[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(
        raw,
      )
    );
  if (raw.split("?")[0] === "/api/v1/assets/export/selection-v2")
    return selectionExportV2Enabled === true && method === "GET";
  if (raw.split("?")[0] === "/api/v1/assets/export/selection")
    return selectionExportEnabled === true && method === "GET";
  if (raw === "/api/v1/assets/import/v3")
    return (
      method === "POST" &&
      importV3Enabled === true &&
      importEnabled === true &&
      datesEnabled === true &&
      locationEnabled === true
    );
  if (raw.split("?")[0] === "/api/v1/assets/export/v4")
    return exportV4Enabled === true && method === "GET";
  if (raw.split("?")[0] === "/api/v1/assets/export/v3")
    return exportV3Enabled === true && method === "GET";
  if (raw.split("?")[0] === "/api/v1/assets/locations/overview")
    return locationEnabled === true && method === "GET";
  if (raw.split("?")[0] === "/api/v1/assets/locations/inventory")
    return locationEnabled === true && method === "GET";
  if (
    /^\/api\/v1\/assets\/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\/location$/.test(
      raw,
    )
  )
    return locationEnabled === true && ["GET", "PUT"].includes(method);

  if (
    /^\/api\/v1\/assets\/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\/dates$/.test(
      raw,
    )
  )
    return datesEnabled === true && ["GET", "PUT"].includes(method);
  if (raw.split("?")[0] === "/api/v1/assets/warranty/overview")
    return datesEnabled === true && method === "GET";
  if (raw.split("?")[0] === "/api/v1/assets/warranty")
    return datesEnabled === true && method === "GET";
  if (raw === "/api/v1/assets/export/v2")
    return datesEnabled === true && method === "GET";
  if (raw === "/api/v1/assets/import/v2")
    return (
      method === "POST" &&
      importV2Enabled === true &&
      importEnabled === true &&
      datesEnabled === true
    );
  if (method === "POST" && raw === "/api/v1/assets/import")
    return importEnabled === true;
  const path = raw.split("?")[0];
  if (
    method === "GET" &&
    /^\/api\/v1\/assets\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      raw,
    )
  )
    return true;
  if (method === "GET")
    return [
      "/api/v1/csrf-token",
      "/api/v1/auth/profile",
      "/api/v1/assets",
      "/api/v1/assets/export",
      "/api/v1/assets/overview",
      "/api/v1/assets/serial-duplicates",
    ].includes(path);
  if (method === "POST")
    return [
      "/api/v1/auth/register",
      "/api/v1/auth/login",
      "/api/v1/assets",
    ].includes(path);
  return method === "PUT" && /^\/api\/v1\/assets\/[a-f0-9-]{36}$/i.test(path);
}

/** Remove hop headers, including headers nominated by Connection. */
export function cleanHeaders(headers) {
  const excluded = new Set([
    ...hop,
    ...String(headers.connection ?? "")
      .toLowerCase()
      .split(",")
      .map((v) => v.trim()),
    "host",
  ]);
  return Object.fromEntries(
    Object.entries(headers).filter(([key]) => !excluded.has(key.toLowerCase())),
  );
}

/** Build bounded routing with an injectable transport for offline contract tests. */
export function createHandler(config, request = http.request) {
  validateConfig(config);
  const { upstreamPort, fixtureId, timeoutMs = 15000 } = config;
  const recoveryFault =
    config.recoveryRequestId === undefined
      ? null
      : createRecoveryFault({
          syntheticOnly: true,
          importEnabled: config.importEnabled,
          requestId: config.recoveryRequestId,
          schemaVersion: config.importV3Enabled
            ? 3
            : config.importV2Enabled
              ? 2
              : 1,
        });
  return async (req, res) => {
    const fail = (code) => {
      if (res.writableEnded || res.destroyed) return;
      if (!res.headersSent) {
        res.writeHead(code, {
          "content-type": "application/json",
          "cache-control": "no-store",
        });
        res.end('{"error":"Fixture request failed"}');
      } else res.destroy();
    };
    const timer = setTimeout(() => {
      fail(504);
      req.destroy();
    }, timeoutMs);
    let upstream;
    res.on("close", () => {
      clearTimeout(timer);
      upstream?.destroy();
    });
    if (
      req.method === "GET" &&
      req.url === `/__asset_desk_fixture/${fixtureId}`
    ) {
      res.writeHead(200, {
        "content-type": "application/json",
        "cache-control": "no-store",
      });
      res.end(
        JSON.stringify({
          fixtureId,
          syntheticOnly: true,
          ...(recoveryFault ? { recoveryFault: recoveryFault.status() } : {}),
        }),
      );
      return;
    }
    if (
      !allowed(
        req.method,
        req.url,
        config.importEnabled,
        config.datesEnabled,
        config.importV2Enabled,
        config.locationEnabled,
        config.exportV3Enabled,
        config.importV3Enabled,
        config.selectionExportEnabled,
        config.checkEnabled,
        config.selectionExportV2Enabled,
        config.exportV4Enabled,
      )
    ) {
      fail(404);
      req.resume();
      return;
    }
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req.iterator({ destroyOnReturn: false })) {
        size += chunk.length;
        if (size > limit) {
          // Do not tear down the shared socket before the error is flushed.
          // Returning from the default async iterator would also destroy req.
          req.pause();
          res.once("finish", () => req.destroy());
          fail(413);
          return;
        }
        chunks.push(chunk);
      }
      const body = Buffer.concat(chunks);
      const faultSelected =
        recoveryFault?.claim(req.method, req.url, body) ?? false;
      upstream = request(
        {
          hostname: "127.0.0.1",
          port: upstreamPort,
          path: req.url,
          method: req.method,
          headers: {
            ...cleanHeaders(req.headers),
            "content-length": body.length,
          },
          agent: false,
        },
        (incoming) => {
          const parts = [];
          let bytes = 0;
          incoming.on("data", (chunk) => {
            bytes += chunk.length;
            if (bytes > limit) {
              fail(502);
              upstream.destroy();
            } else parts.push(chunk);
          });
          incoming.on("error", () => fail(502));
          incoming.on("end", () => {
            if (res.writableEnded || res.destroyed) return;
            if (incoming.statusCode >= 300 && incoming.statusCode < 400) {
              fail(502);
              return;
            }
            if (incoming.complete !== true) {
              fail(502);
              return;
            }
            // Consume the complete bounded successful response before losing its acknowledgement.
            // Ordinary fixture profiles never construct this one-shot fault.
            if (
              recoveryFault?.complete(
                faultSelected,
                incoming.statusCode,
                incoming.complete === true,
              )
            ) {
              res.destroy();
              return;
            }
            const output = Buffer.concat(parts);
            res.writeHead(incoming.statusCode, {
              ...cleanHeaders(incoming.headers),
              "content-length": output.length,
              "cache-control": "no-store",
            });
            res.end(output);
          });
        },
      );
      upstream.on("error", () => fail(502));
      upstream.end(body);
    } catch {
      fail(502);
    }
  };
}

/** Create an inert TLS server; caller explicitly owns listen/close and TLS loading. */
export function createProxy(tls, config) {
  validateConfig(config);
  const timeoutMs = config.timeoutMs ?? 15000;
  const server = https.createServer(tls, createHandler(config));
  server.requestTimeout = timeoutMs;
  server.headersTimeout = timeoutMs;
  server.timeout = timeoutMs;
  return server;
}
