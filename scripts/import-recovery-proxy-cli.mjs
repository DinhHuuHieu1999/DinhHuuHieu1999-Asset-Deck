import { readFileSync } from "node:fs";
import {
  createProxy,
  parseProxyArgs,
  validateConfig,
} from "./client-https-proxy.mjs";

/** Dedicated recovery CLI, separate from ordinary/native fixture profiles. */
export function parseRecoveryProxyArgs(args) {
  if (args.length !== 9 || args[7] !== "--lose-import-ack")
    throw new Error("Explicit recovery profile required");
  const parsed = parseProxyArgs(args.slice(0, 7));
  const config = { ...parsed.config, recoveryRequestId: args[8] };
  validateConfig(config);
  return { ...parsed, config };
}

// A module import never reads TLS or starts a listener.
export function runRecoveryProxy(args) {
  const { config, port, cert, key } = parseRecoveryProxyArgs(args);
  const server = createProxy(
    { cert: readFileSync(cert), key: readFileSync(key) },
    config,
  );
  server.on("error", () => {
    process.exitCode = 1;
    server.close();
  });
  server.listen(port, "127.0.0.1");
  process.on("SIGTERM", () => {
    server.closeAllConnections();
    server.close();
  });
  return server;
}
