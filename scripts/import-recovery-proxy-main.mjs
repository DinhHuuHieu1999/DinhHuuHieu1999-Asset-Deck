import { runRecoveryProxy } from "./import-recovery-proxy-cli.mjs";
try {
  runRecoveryProxy(process.argv.slice(2));
} catch {
  process.stderr.write("Recovery fixture TLS startup refused\n");
  process.exitCode = 1;
}
