const requestKey =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** One-shot test-only fault selector; never reads files or opens a listener. */
export function createRecoveryFault({
  syntheticOnly,
  importEnabled,
  requestId,
  schemaVersion = 1,
}) {
  if (
    ![1, 2, 3].includes(schemaVersion) ||
    syntheticOnly !== true ||
    importEnabled !== true ||
    typeof requestId !== "string" ||
    !requestKey.test(requestId)
  ) {
    throw new Error("Explicit synthetic recovery fault required");
  }
  let claimed = false;
  let suppressed = false;
  return Object.freeze({
    claim(method, path, bytes) {
      if (
        claimed ||
        method !== "POST" ||
        path !==
          (schemaVersion === 3
            ? "/api/v1/assets/import/v3"
            : schemaVersion === 2
              ? "/api/v1/assets/import/v2"
              : "/api/v1/assets/import") ||
        !Buffer.isBuffer(bytes) ||
        bytes.length > 1024 * 1024
      )
        return false;
      let body;
      try {
        body = JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
      } catch {
        return false;
      }
      if (!body || Array.isArray(body) || body.requestId !== requestId)
        return false;
      claimed = true;
      return true;
    },
    complete(selected, status, complete) {
      if (
        !selected ||
        !claimed ||
        suppressed ||
        complete !== true ||
        !Number.isInteger(status) ||
        status < 200 ||
        status >= 300
      )
        return false;
      suppressed = true;
      return true;
    },
    status() {
      return { claimed, suppressed };
    },
  });
}
