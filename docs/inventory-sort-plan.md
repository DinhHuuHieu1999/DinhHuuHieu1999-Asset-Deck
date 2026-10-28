# Inventory sorting

Status: source, offline, PostgreSQL, HTTPS and operator Windows functional checks
verified. Native lifecycle cleanup is verified. Codacy and commit approval remain
pending.

Inventory accepts `sort=updated_desc` (default) or `sort=name_asc` on the
regular, warranty and location-aware list endpoints. Predicates still run before
ordering and fixed-size pagination. Updated order remains `updated_at DESC,id DESC`.
Name order is exact, case-sensitive PostgreSQL `COLLATE "C"` ascending with ID
ascending as the unique tie-breaker; it is not locale-aware natural sorting.
Only fixed allowlisted SQL fragments are used. Invalid values are rejected.
Export order and payloads, overview counts, ownership, schema and dependencies
remain unchanged. Concurrent writes may shift offset pages as before.

The client exposes Recent updates (Updated most recently) and Name A-Z.
Apply starts page one;
Refresh and pagination retain the last applied sort. Failed requests retain the
prior rows and applied-sort identity. Overview drill-down preserves the applied
sort; Back leaves drafts and applied state unchanged. No local page-only sorting.
Synthetic baseline and updated renders were inspected at 390, 768 and 1440 pixels
with 200% text scaling.

## Offline verification

- Backend full suite after fixture-test correction: 628 tests passed; 66 opt-in
  database assertions skipped. Typecheck passed.
- Flutter final full suite: 774 tests passed; one opt-in test skipped. Analyzer reported no issues.
- Sort contracts cover all three list paths, default/invalid input, transport,
  Apply/Refresh/pagination, retained results on failure and overview drill-down.
- These checks do not certify real PostgreSQL ordering or native interaction.

## Acceptance still required

- Codacy review or explicit scoped exception; explicit commit approval.

Codacy remains unavailable, not PASS: the installed MCP installer omits the
required root path and fails before installation. No external package or MCP
configuration was patched, and no exception is assumed.

## PostgreSQL fixture

`scripts/sort-postgres-fixture.py` selects only the fixed sort profile in the
existing owned, 120-second lifecycle. It requires explicit `--execute-synthetic`
and a locally available `--image sha256:...`; it never pulls an image or retries.
It creates a synthetic database/container/volume and binds one port to loopback.
Cleanup verifies ownership, stops the container and retains data/evidence.

Four opt-in assertions cover all three list paths across the 50-row boundary,
literal filters, owner isolation, duplicate names, case/non-ASCII C ordering,
unchanged rows, and legacy timestamp/ID ordering. Without fixture opt-in they skip;
skipped assertions are not acceptance. Four new lifecycle tests and eight existing
lifecycle tests pass offline; the new Jest suite typechecks.

Execution requires separate operator approval. Do not use a regular database URL.

### First isolated run

The approved one-shot run completed three assertions and failed the default-order
assertion. Its query allowed every status, so the deliberately retired row also
matched Search through its serial; the expected IDs included only stored rows.
The test now explicitly filters stored status. Product code was not changed.
Evidence: `.local/asset-sort-c88a1f22d90f3dfe937f882b23590178/`.
Ownership cleanup reports stopped; container and volume are retained. No retry
was performed. The correction was not executed against that retained database.

### Separately approved corrected run

A new isolated fixture passed all four assertions with zero failures or skips.
Evidence: `.local/asset-sort-57894335c64c1f299fbc308aafce052e/`.
The lifecycle verified ownership and stopped its container, retaining its volume.
This proves the repository sorting contracts on PostgreSQL, not HTTPS/client or
Windows acceptance. No regular database, deployment or commit was changed.

## HTTPS acceptance

`scripts/sort-https-fixture.py` reuses the fixed location-enabled TLS lifecycle.
It requires a separately built candidate, existing PostgreSQL image, explicit
synthetic opt-in, loopback ports, local TLS paths and the existing Dart executable.
No dependency installation, certificate trust changes or automatic retry occurs.
The driver checks the random marker before registering synthetic accounts and
keeps normal TLS/hostname verification. No private account data is printed.

The HTTP stage sends invalid, repeated and nested sort queries to all three list
routes, with required warranty fields only on the warranty route. The Dart stage
checks 53 matching rows across pages, name/ID ordering, both owners, dates/location
predicates, unchanged versions and recent/default ordering. Source/artifact hashes
must remain unchanged during acceptance. Exact typed output is mandatory.

Five Python orchestration tests and two Dart comparator tests pass offline;
Flutter analyzer reports no issues. These offline checks alone do not certify HTTPS, native UI, restart or deployment. Further builds/runs need separate approval. Codacy and commit approval remain
pending.

### Approved HTTPS run

The backend candidate build and one separately approved HTTPS fixture completed.
HTTP validation rejected invalid/repeated/nested sort on all three routes. The
real Dart client passed all three sorted list paths across 53 matching rows,
owner isolation, recent/default ordering and unchanged versions.
Evidence: `.local/asset-client-1b002bae483530bd400586458466e2b6/result.json`.
All 34 selected source hashes still match the pre-run source review; linked check:
`.local/inventory-sort-review/https-acceptance.json`.
The HTTPS lifecycle reports completed and cleanup stopped. Native results are
recorded separately below; no regular backend/database was changed.

## Operator-confirmed Windows checks

The separately approved release candidate built successfully with the existing SDK
and `--no-pub`, then opened on the isolated location/date-enabled HTTPS fixture.
The operator confirmed Name A-Z order, Refresh retaining order/applied identity,
unapplied sort selection not affecting Refresh, applying recent-updates order,
and Inventory overview -> Back preserving Name A-Z without choosing a drill-down.
Evidence: `.local/inventory-sort-review/native-manual-acceptance.json`.

This is functional acceptance only, not screen-reader/text-scaling, recovery or
deployment acceptance. The native lifecycle ended and reported cleanup stopped; its retained evidence is
`.local/asset-client-bd9196290a8a87647899364b7aa31a2e/result.json`.
Codacy is unavailable, not PASS; no current-phase exception or commit is approved.
