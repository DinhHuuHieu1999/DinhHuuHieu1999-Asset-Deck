# Refresh asset details

Status: source/tests approved. Backend/client/UI implemented; synthetic renders inspected.
PostgreSQL and Dart HTTPS acceptance passed; native acceptance pending.
No commit or deployment.

## Contract

`GET /api/v1/assets/:id` requires existing asset authentication, a UUID path,
and the existing assets feature flag. It returns the same base asset shape as
the inventory list, with `Cache-Control: no-store`. Missing and foreign IDs both
return 404 without revealing ownership. Static routes remain before `:id`.
No new migration, dependency or write operation is introduced.

## Client and UI acceptance

Add an explicit Refresh action to details, not automatic polling or retry.
Fetch the base asset by ID, then verify enabled dates/location against its ID and
version using existing contracts. Publish only a complete verified snapshot.
On failure retain the previous complete snapshot, label it stale and disable
editing until successful refresh. Never substitute Unknown for failed reads.
A session change clears private data and discards late responses. Ignore older
requests and source replacements. Back preserves inventory search/filter/sort;
refreshing details must not silently rewrite the inventory's applied filters.
Even a successfully refreshed snapshot is not a continuously live record.

Capture and inspect the current synthetic render before UI changes, then compare
after at 390/768/1440 pixels and 200% text. Cover success, not-found, version
mismatch, offline error, session invalidation, late response and Back in tests.
Live PostgreSQL/HTTPS and Windows acceptance require separate scoped execution.

## Verification so far

Backend typecheck and ten focused read/serial tests passed. Repository tests
verify SQL owner/ID binding and no query for invalid owners. Service/controller
tests cover not-found, authenticated owner extraction and error propagation.
These mock tests do not prove live SQL isolation, HTTP routing or UUID pipes.

Client transport tests cover authentication, invalid path IDs and wrong response
identity. Refresh widget tests cover complete replacement, failure/recovery,
wrong identity/version, session invalidation and source replacement. Synthetic
renders at 390/768/1440 pixels with 200% text were inspected; no overflow was
observed. These do not replace native accessibility or live HTTP/SQL acceptance.

A full backend regression passed 692 tests with 77 opt-in cases skipped, after
adding HTTP mock coverage for authentication, UUID validation, fixed owner,
no-store, unavailable records and static serial-route precedence. PostgreSQL
isolation was subsequently verified as described below. The real authenticated
HTTPS stack remains pending; synthetic auth
in the HTTP tests does not certify JWT verification.

## Opt-in fixture verification

- `scripts/details-postgres-fixture.py` selects four repository assertions:
  owned read beyond page one, foreign/absent isolation, unchanged snapshots,
  and latest committed version. It reuses the bounded ownership-checked lifecycle.
- `scripts/details-https-fixture.py` selects the real Dart client driver:
  owned read, two-owner isolation, unchanged read snapshots and updated version.
- Both require explicit synthetic execution; neither runs during offline tests.
  HTTPS, native Refresh and live cache-header acceptance remain pending.
- No new migration, dependency, trust change or regular database access is required.

One approved PostgreSQL run completed all four assertions with no skipped or
failed tests. The owned container was stopped and its volume retained. Evidence:
`.local/asset-details-00c42200e63fd80e9e85fdb3007618b7/result.json` and
`jest-result.json` (local-only, not required source artifacts).
This proves repository behavior only, not TLS, auth or native UI behavior.

The first HTTPS attempt reached the dedicated acceptance callback but failed;
cleanup completed. Evidence is retained under
`.local/asset-client-298aacdcf7b6c9cb6ce14e7102e4715a/`.
The test proxy did not allow the new UUID GET route. Its source now allows only
that exact read path, with regression coverage rejecting adjacent paths,
malformed IDs and destructive methods (34 proxy tests passed).
At that checkpoint the correction had not been validated by live HTTPS.
The failed attempt remains a failure; the approved follow-up is recorded below.

The separately approved follow-up HTTPS run completed with
`detailsDartClient: true`, `syntheticOnly: true` and `cleanup: stopped`.
Evidence: `.local/asset-client-e327db25f0828de33ece217088745d49/result.json`.
The real Dart client verified owned reads, two-owner isolation, unchanged read
snapshots and the latest updated version. This does not certify native Refresh,
live cache headers or accessibility. The shared CLI still prints a legacy serial
success label; the details-specific result fields are the acceptance evidence.

## Native acceptance checklist (pending)

Use a new synthetic HTTPS fixture, existing SDK/cache and a separately approved
Windows candidate. Enable dates/location, preserve TLS validation and stop if
Application Control blocks execution; do not retry or change machine security.

1. Open View details and press Refresh details. Verify the current name, serial
   and status, with no duplicate success messages.
2. Save notes through Edit asset, reopen details and Refresh. Verify saved notes.
3. Save purchase `2024-02-29`, expiry `2027-02-28` and location
   `Synthetic room %_1`; Refresh details and verify all fields remain correct.
4. From inventory apply Search `Synthetic`, open details, Refresh then Back.
   Verify the applied search, sort and list are preserved.
5. Close the app to end the owned fixture. Record only observed results;
   synthetic widget tests do not certify native accessibility or offline errors.

## Operator-observed Windows checks

The operator confirmed base fields survive Refresh, edited notes are retained,
purchase/expiry/location remain correct after Refresh, and Back preserves Search
`Synthetic` with one asset. Evidence is recorded in local manual acceptance files
for sessions `85d20fd3f7b66fc5e00b7d779667d207` and
`4b0f79629692474afb8638750aa786c3`. This covers the listed functional checks only;
native offline failures and screen-reader behavior are not certified.
Final fixture shutdown must be verified separately. No commit/deployment approval
is implied by these results.
