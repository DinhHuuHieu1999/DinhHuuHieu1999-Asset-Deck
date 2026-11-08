# Duplicate serial warning

Status: backend/client/editor source implemented and synthetic Windows warning
interaction accepted. Not deployed; analyzer findings review remains pending.

- Compare trimmed, case-sensitive serial labels using literal equality. `%` and
  `_` are ordinary characters; blank serials never produce a duplicate warning.
- Check the authenticated owner's complete inventory, independently of list
  filters and pagination. Editing excludes the current asset ID.
- Return only a boolean, not other records, counts or ownership information.
- This is advisory, not a uniqueness constraint or reservation. Concurrent writes
  may change the result. Existing create/update/import behavior remains unchanged.
- Editor interaction: explicit check, amber warning when matched,
  and a clear unavailable state on failure. Never describe a failed check as clear.
  Editing the serial invalidates the previous check; Save remains available.
- Baseline and warning renders inspected at 390/768/1440 pixels with 200% text.
  Captures use a synthetic font/icon fallback, not native accessibility evidence.

No dependency, schema migration, fixture, build, deployment or commit is included
in the source approval.

## API and verification

`GET /api/v1/assets/serial-duplicates?serial=...&excludeId=...` requires the
existing asset authentication boundary and returns only `{duplicate: boolean}`
with `Cache-Control: no-store`. The optional exclusion must be a UUID. Input is
limited to 120 Unicode code points without NUL; query values remain parameterized.
This read uses the existing assets domain flag, with no separate schema or flag.
Serials are plaintext inventory data: do not log or publish query strings.

- Backend typecheck and 684 unit tests passed; 73 opt-in cases skipped.
- Six serial backend tests cover SQL binding/owner scope, strict response shape,
  normalization, input validation and authenticated owner extraction.
- Eleven focused Flutter parser/editor/render tests passed; analyzer is clean.
- Three new mock transport tests cover authentication, literal query/exclusion,
  malformed/server errors, no retries and late-session rejection.
- Final full Flutter suite: 881 passed, one opt-in case skipped.

Codacy MCP was called for all 14 scoped files; every response was an empty
`result` array. This does not identify an analyzer or prove coverage, so it is
recorded as incomplete, not Codacy/security PASS.

A separately approved isolated PostgreSQL fixture passed all four repository
scenarios: literal/case-sensitive matching, owner isolation and own-ID exclusion,
lookup beyond the first page without mutation, and duplicate create/update allowed.
The owned container was stopped and its volume retained; no retry was performed.

A separately approved HTTPS run also passed authentication/DTO checks and the
real Dart client scenarios with two synthetic accounts; owned resources stopped
safely. See the [HTTPS acceptance plan](inventory-serial-https-plan.md).
Native checks are recorded separately below; screen-reader behavior, complete
Codacy coverage and deployment remain unverified. HTTP acceptance does not prove
native behavior.

Repository fixture source and offline boundaries are described in the
[serial fixture plan](inventory-serial-fixture-plan.md). Live execution remains
separately gated.

## Native review

The operator confirmed duplicate writes remain allowed, Refresh shows two assets,
unique serial checks, invalidation after editing serial, Keep/Discard draft behavior
and Tab/Enter/Space activation on the first Windows candidate. A subsequent
operator-requested amber warning style passed eleven editor tests, including
light/dark contrast of at least 4.5:1, and inspected 200% text renders. The amber
revision was rebuilt and the operator confirmed the warning visible on a fresh
Windows synthetic fixture. Screen-reader
behavior and Codacy coverage remain unverified.

## Local analyzer follow-up

The opt-in ESLint candidate/runner is committed separately as `2e48350`; it does
not activate a live MCP/config switch or waive findings. The latest two-file scan
reported 89 findings in `asset-serial.postgres.spec.ts` and one in
`serial-fixture-cleanup.test.mjs`, without fatal errors or source changes.
These counts are not a full-feature scan or a security PASS. Dart local analyzer
coverage remains unsupported by the installed Codacy tooling. Product source,
fixture cleanup changes and findings acceptance are not included in that tooling
commit.
