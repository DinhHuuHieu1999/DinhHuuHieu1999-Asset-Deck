# Check-date selection export proposal

Status: design only. Source implementation, fixtures and commit require separate
review. Existing selection schema v1 and full inventory v1/v2/v3 stay unchanged.

## Purpose

Save the complete owner-scoped list matching the last applied inventory filters,
including the manual check-date predicate. It is a private selection, not a full
account backup, automatic inspection result or import request.

## Proposed contract

- Keep format `asset-desk-inventory-selection`; introduce schema version 2 on a
  separate endpoint. Do not silently extend the strict v1 filter/record parser.
- Retain `scope=filtered-selection`, `allMatchesIncluded=true`, exact UTF-8 payload
  checksum, canonical existing filters and deterministic sorting.
- Add `filters.check` as one tagged object: `{mode: all}`, `{mode: unknown}`,
  `{mode: before, cutoff: YYYY-MM-DD}` or
  `{mode: on_or_after, cutoff: YYYY-MM-DD}`. Unknown/all forbid a cutoff; dated
  modes require a real calendar date in years 0001 through 9999. No implicit today.
- Each public record adds `lastCheckedDate`: a strict calendar date or null.
  All existing public fields remain. Do not expose owner identifiers or receipts.
- Capture dates, locations and check dates in the same SQL statement snapshot.
  Bind the authenticated owner and all predicates before ordering and the 501-row
  sentinel. Never join page responses into an apparently complete selection.
- Retain limits of 500 records and 1 MiB for the entire envelope. Fail on overflow,
  malformed counts/dates or unsupported capabilities; never truncate or downgrade.

## Compatibility and controls

The endpoint is authenticated, no-store and rejects extra/repeated/nested query
parameters. A new optional flag defaults off and requires selection export plus
manual check-date capabilities. No migration or production dependency is planned.

Flutter captures applied filters, not draft controls. Prepare is explicit. The
preview shows check mode/cutoff and private-data warnings. Save cancellation keeps
the result; failed Prepare clears it; session changes invalidate private results.
Inspect supports v1 and v2 through explicit version dispatch. Existing import
continues rejecting every selection format/version. No import implementation is
part of this phase. Reuse the native selection writer only if existing bounded
size, file naming and no-overwrite behavior are sufficient.

## Required acceptance

1. Pure contract tests: every mode, leap dates, boundary equality, forbidden cutoff,
   unknown keys, mismatched scope, null dates, checksum and byte/record limits.
2. Repository tests: all combined filters, two owners, deterministic order, empty
   result, 500/501 rows and concurrent edits with one consistent snapshot.
3. API/client: auth, capability-off behavior, strict query validation, no-store,
   exact response filter matching and late-response/session invalidation.
4. UI: capture baseline before edits; Prepare uses applied scope even with unsent
   drafts. Save/Cancel and Inspect cover valid and corrupt files at 200% text.
5. Opt-in fixtures and native acceptance are separately approved. Offline passes
   do not certify database concurrency, HTTPS, native dialogs or accessibility.

## Decision boundary

Implement only after contract review. Do not repurpose v1, enable deployment flags,
run services, upload files or commit under this design approval.

## Current implementation boundary

Backend v2 serializer, owner-scoped single-statement repository, authenticated
`GET /assets/export/selection-v2` controller and module registration are present.
`ASSET_SELECTION_EXPORT_V2_ENABLED=false` defaults off and requires selection
export plus manual check-date capabilities. Readiness checks the existing
`last_checked_on` column without applying migrations. Query keys `checkMode` and
`checkCutoff` map to the strict tagged payload filter; all modes are explicit.

The Dart v2 parser validates exact fields, dates, checksum and record membership
in the requested check bucket. Its client method compares response scope with
the requested scope after digest verification and rechecks the session epoch.
Existing v1 parsers, client methods and import behavior remain unchanged.

Offline checks: backend typecheck and 55 serializer/repository/controller/config
tests; 27 additional v1/v2 HTTP tests with synthetic auth and mocked SQL; Flutter
analyzer and 153 parser/transport regression tests. These offline checks do not certify real database or HTTPS behavior,
feature-off startup, UI or native acceptance. Separate PostgreSQL evidence is
recorded below. Codacy MCP returned empty
result arrays, not proof of analyzer coverage or a security PASS.

The v2 UI is implemented behind a separate default-off flag; native acceptance is pending. The HTTPS harness has separate synthetic acceptance below. Source changes remain uncommitted.
Separate review is required before fixture execution, UI edits or deployment.

## PostgreSQL harness and isolated acceptance

The opt-in `scripts/selection-export-v2-postgres-fixture.py` reuses the owned,
bounded repository lifecycle with a distinct fixture identity. It requires an
explicit immutable local image ID and `--execute-synthetic`; execution needs
separate operator approval. No pull, retry or regular database access is allowed.
The total runtime deadline is 120 seconds; cleanup verifies ownership, stops the
container and retains the volume and evidence.

Eight opt-in repository scenarios cover public fields/checksum, owner isolation
and no writes, 500/501 and byte limits, combined literal filters before limits,
warranty/location boundaries, deterministic ordering, concurrent snapshot edits
including the check date, and unknown/strict/inclusive check-date boundaries.
These scenarios are skipped by default. Offline lifecycle tests mock every
process; passing them does not certify PostgreSQL behavior.

Offline validation: 12 lifecycle tests (v1 and v2), backend typecheck and 27 v2
contract tests passed. PostgreSQL scenarios remain skipped in default tests.

A separately approved one-shot synthetic PostgreSQL run passed all eight
scenarios with zero failures or skips. Evidence is retained locally at
`.local/asset-selection-v2-9df946026716ceb1b38b38f55ed00ce7/` in `result.json`
and `jest-result.json`. The runner reported `cleanup: stopped`; container and
volume were retained. No retry, pull, regular database change, HTTPS or native
acceptance is claimed.

## HTTPS harness and isolated acceptance

`scripts/selection-export-v2-https-fixture.py` selects an explicit v2 refinement
of the existing isolated selection lifecycle. Preflight requires the v2 build
and check-date artifacts and fixed Dart driver before TLS reads or resource
creation. The proxy enables required selection/check/date/location capabilities;
import routes remain disabled.

The driver uses the actual Dart transport/parser with default TLS verification,
two synthetic accounts and Python SHA-256 over stdin. Assertions cover anonymous
and signed-out refusal, no-store, invalid queries, 51 matches, literal/combined
filters, strict/inclusive check-date boundaries, owner isolation, unchanged v1
export and no writes during reads. Every correctly typed report check is required;
partial output cannot pass. Reports exclude payloads and credentials.

The separately approved backend build and one-shot HTTPS fixture completed
successfully, without retry. The actual Dart client passed the complete report
contract; evidence is retained in
`.local/asset-client-b51c466e9df74a8fa77428a0a9489d9c/result.json`.
The runner recorded source hashes and `cleanup: stopped`. Fixture processes were
stopped and the synthetic volume was retained. Existing localhost TLS material
was used without changing trust or the regular backend. That run did not cover native dialogs or UI; no deployment or commit is implied.

## Optional v2 UI

`ASSET_DESK_ENABLE_SELECTION_EXPORT_V2` defaults off and requires the existing
selection, check-date, date and location capabilities. The separate v2 export
uses only successfully applied inventory filters, never draft controls. Existing
v1 export remains unchanged and refuses unsupported check-date filters.

V2 saves through the existing selection-only native channel with the same private
filename behavior. Its separate read-only inspector displays manual check dates
and tagged filters. Cancel retains preview/checksum evidence; choosing invalid
bytes clears both. No selection schema is accepted for import.

Synthetic render checks cover widths 390, 768 and 1440 at 200 percent text. Navigation tests verify applied Unknown/Before scope rather than draft controls,
Back preserving draft values, both separate routes and default-off visibility.
Flutter analyzer and the full suite passed: 998 tests, one opt-in skipped.
Source tests and screenshots do not substitute for native checks; the separately
approved Windows acceptance below covers the exercised native paths. Synthetic captures use a local
font; missing non-Latin/icon glyphs in the harness are not native rendering proof.

## Native fixture preparation

The opt-in native runner requires the exact v2, selection, manual check, date,
location and export-v3 build capabilities. Its hashed deployment remains pinned
to a separate loopback HTTPS endpoint. Offline native contracts: 34 tests pass.
A separate release build succeeded using the existing SDK/cache and `--no-pub`.
The operator confirmed Prepare with one asset, Save followed by Inspect with
matching checksum and Unknown check date, Cancel retaining preview/checksum, and
invalid JSON clearing both. Python independently verified the saved schema v2,
one-record payload and exact UTF-8 SHA-256. Private evidence is retained under
`.local/check-selection-ui/` and fixture
`.local/asset-client-7c5fb2e39acf10e79651bb83a57d91c5/`.
This does not certify all native accessibility paths or non-Unknown check dates.
Fixture cleanup is recorded separately by its terminal result, not inferred from
operator acceptance. Codacy is unavailable, not a passing security gate. No
commit, push or regular-backend deployment is implied.
