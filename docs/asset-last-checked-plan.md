# Manual inventory check date

Status: approved source/tests phase; backend/client read/update and unchecked-filter candidate with Details/editor and unchecked-filter UI.

Record a manual `lastCheckedOn` calendar date, or explicit null to clear it.
This is an operator assertion, not evidence of automatic device discovery or a
successful physical inspection. Do not infer it from purchase, warranty, updates,
import or opening Details. Existing records remain Unknown.

## Contract

- Optional backend `ASSET_CHECK_ENABLED` defaults off; enabled startup must check
  migration 006 without creating schema. No new dependency is planned.
- Read/update use authenticated owner and asset UUID. Update requires the shared
  asset version, changes only check date/version/update timestamp, and never retries.
- Strict Gregorian `YYYY-MM-DD`, years 0001–9999; no timestamps or silent trimming.
  Reject dates later than the server UTC calendar day. UI must state this reference
  rather than imply that local midnight and UTC midnight are equivalent.
- Read-only Details shows the date or Unknown; explicit edit supports clear,
  Keep/Discard, conflict and unknown write outcome without losing the draft.
- An explicit unchecked filter selects SQL NULL before pagination, combined with
  existing search/status/category/location/warranty/sort. Reset clears this filter;
  Refresh and Back preserve the last applied selection.
- Existing export/import versions remain byte-contract compatible and exclude this
  new field. State that limit visibly; no new export schema is implicit.

## Verification and execution boundary

44 offline tests cover strict payload/date/version/config and mocked persistence
boundaries; backend typecheck passes. Read/update routes are registered only when
the flag is enabled. Real JWT authentication and production HTTP integration remain pending; mocked SQL assertions do not prove database behavior. Capture and inspect current UI
before changing it. Then test owner isolation, shared-version conflicts, null filter
before pagination, date preservation, cancellation and delayed session responses.
SQL/HTTPS/native fixture execution needs separate approval. The approved SQL
run is recorded below; HTTPS/native remain pending. Migration 006 is source only and may require an exclusive table lock; its
five-second lock timeout fails rather than waiting indefinitely. A later rollout
requires backup and sizing/lock review. Rollback disables the feature and retains
schema/data, not a destructive down migration. No commit or deployment is implied.

Read/update routes: `GET /api/v1/assets/:id/check-date` and
`PUT /api/v1/assets/:id/check-date`, both no-store. PUT requires exactly
`version` and `lastCheckedOn`; all query parameters are rejected. Global CSRF
middleware applies to PUT. Optional startup probes migration 006 columns.

Additional candidate evidence: three HTTP tests use real Nest routing, UUID pipes
and CSRF service with a synthetic auth guard and mocked persistence. They do not
certify real JWT or PostgreSQL. The focused Dart model/transport suite passes 111
tests, including explicit clear, wrong identity, malformed input and no-retry
version mismatch. The unchecked filter now reaches base, warranty and location inventory endpoints;
SQL contract tests verify NULL before pagination. These are not real SQL execution
checks. UI integration now has focused offline regression coverage.

## Editor source progress

The standalone check-date editor now supports explicit save/clear, UTC future-date
validation, Keep/Discard, and draft preservation after conflict or unknown write
outcomes. Eight focused widget tests pass, including 390/768/1440 layouts at 200%
text. The narrow render exposed a truncated field label; it was shortened while
keeping the date format in wrapping instructions. Navigation wiring and the unchecked filter are implemented behind
`ASSET_DESK_ENABLE_ASSET_CHECK` (default false). Apply is explicit; Refresh retains
the applied choice and Reset clears it. Matching selection export is disabled for
this filter because the existing selection schema cannot represent it. Full
exports remain independent and exclude check dates. No live fixture or native acceptance is claimed.

## Offline regression checkpoint

Backend typecheck passes; 736 backend tests pass and 81 opt-in tests skip.
Flutter passes 926 tests with one opt-in skip; analyzer reports no issues.
The enabled filter was rendered and inspected at 390/768/1440 widths with 200%
text. Its label now says Unknown rather than never checked: clearing a date also
matches this filter. The render harness scrolls the lazy list explicitly so it
works without the optional capture font. These checks do not certify PostgreSQL,
real authentication, HTTPS or Windows native behavior. No commit is authorized.

The [PostgreSQL fixture plan](asset-check-postgres-fixture-plan.md) now has a
four-scenario opt-in repository suite. Typecheck passes and all four cases skip
by default without a pool. The fixed-profile bootstrap and 18 focused lifecycle tests now pass offline;
the approved SQL acceptance is recorded below.

Additional filter regressions pass: failed Apply retains the old list/applied
mode; disabled capability makes no check requests; matching export is disabled
only after the Unknown filter is applied and is restored after Reset. The focused
filter suite now passes seven tests. Codacy returned an empty result for this
updated test, not evidence of analyzer coverage or a security pass.

## Repository acceptance

One explicitly approved PostgreSQL fixture passed all four repository scenarios
with no skips/retry. Migration 006 applied in the isolated database; owner/version
checks, preserved fields, clear and filtering before pagination were exercised.
The owned container stopped and synthetic volume/evidence were retained. Regular
backend/database remained unchanged. HTTPS, restart/restore and native acceptance
remain pending; this is not rollout or commit approval. Two additional editor
tests cover pending-save controls and explicit correction after a rejected write
(10 focused editor tests pass).

## HTTPS harness candidate

A fixed exclusive check-date profile and Dart client driver now exist in source.
The driver checks the synthetic TLS marker before registration, two-owner and
shared-version behavior, preserved details, and combined Unknown/location search.
Six profile/wrapper tests plus five existing location profile tests pass offline;
Flutter analyzer is clean. No candidate build, TLS/key read or HTTPS execution has
run. The driver now checks anonymous reads and CSRF-less writes; three argument
regressions reject unsafe endpoints and malformed opt-in. The proxy grants the
exact check-date GET/PUT route only under its dedicated capability; legacy
profiles remain unchanged. Live HTTPS acceptance remains pending. Codacy returns empty results, not
verified coverage or security PASS.

## Current acceptance status

The scoped real Dart HTTPS flow has now passed after correcting the test proxy
capability dispatch. See [HTTPS acceptance](asset-check-https-fixture-plan.md)
for execution evidence and limits; earlier pending statements above are historical
checkpoints, not the current HTTPS status.

The existing native runner now accepts an exclusive `--check-mode` profile with
exact check/date/location build defines. Its handoff describes one synthetic asset
and explicit set/clear/filter checks without preparing an import or claiming a
manual pass. Native runner contracts pass offline. No Windows build or session
has been started for this feature. Native acceptance, restart/restore, rollout,
Codacy coverage and commit remain separate pending gates.

## Windows manual acceptance

The operator confirmed the isolated candidate checks:

- Save `2024-03-01`, Refresh and reopen Details preserves the date.
- Only unknown check dates returns zero assets while the date is set.
- Explicit clear returns one matching asset and Details shows Unknown.
- Keep editing retains the draft; Discard leaves the saved Unknown value intact.
- Details Back and Refresh retain the applied filter, one asset and unchanged
  name/serial/status/notes.

The approved release build used existing SDK/cache with `--no-pub`. The operator
closed the app; the runner reported `session-ended`, `app-closed`, and cleanup
`stopped`. Docker independently confirmed the owned container is exited. Retained
local evidence: `.local/asset-client-b94fc24490b482ecfa6043affd00a16c/`.

This supersedes the native-pending checkpoint above for these specific checks.
It does not establish screen-reader acceptance, restart/restore, regular-service
rollout, Codacy coverage or approval to commit/push. No security settings changed.
