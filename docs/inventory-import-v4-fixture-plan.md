# Import v4 PostgreSQL fixture plan

Execution is opt-in and requires separate approval. Use the existing image by digest,
never pull/install/build. Create a new synthetic owned database/container/volume,
with one ephemeral port bound only to 127.0.0.1. Apply existing migrations 001-006
only inside the fixture, then create its unique ownership marker. No real data,
HTTPS, app launch or regular backend changes.

Run the fixed v4 repository suite with a total 120-second deadline, no retry:

1. 500 records preserve nullable/extreme dates, location and manual check date;
   replay returns exact IDs without additional rows.
2. A changed manual check date conflicts under the same owner/key.
3. V1/v2/v3/v4 keys conflict across schema domains in both directions.
4. Identical keys remain independent across two owners.
5. Concurrent identical operations yield one receipt.
6. Concurrent conflicting content permits only one winner.
7. Injected row failure rolls back all rows and receipt.
8. Lost acknowledgement after real COMMIT permits explicit same-key replay.

Default Jest runs skip all eight cases without creating a pool. The runner refuses
missing files, non-digest images, skips or incomplete reports. Verify ownership
before stopping; keep container, volume and evidence after the run. Offline tests
mock subprocesses; they are not actual PostgreSQL acceptance.

## PostgreSQL acceptance

The approved single run completed all eight scenarios. Evidence is retained locally
under `.local/asset-import-v4-d5ed767fd7283d13be29e8a9805c9cd3/`.
Independent Docker inspection confirmed the matching ownership label, stopped
container and no published ports after cleanup. Container and volume were retained.
This result does not certify HTTPS, Dart transport or native Windows behavior.

## HTTPS driver preparation

`flutter/tool/import_v4_https_acceptance.dart` prepares two synthetic accounts,
uses verified full v4 exports, checks exact receipt replay and owner/session
binding, and compares reexported fields including nullable manual check dates.
It also tests date-only, location-only and check-date-only content conflicts.
Three offline tests exercise the reexport assertion, including changed and lost
manual check dates; Flutter analyzer reports no issues.

The opt-in `scripts/import-v4-https-fixture.py` now selects its own exclusive
profile, applies migrations 001-006 only in the synthetic database, and sets all
child flags explicitly. Its proxy permits only the exact v4 POST route with
required capabilities; older import routes remain disabled. A disabled-module
mode checks authenticated 404 without invoking the Dart import driver.

Negative HTTP cases cover anonymous 401, CSRF 403, malformed/duplicate-key and
invalid/missing calendar fields (400), and proxy body bounds (413), comparing
asset/receipt counts before and after. Checkpoints use fixed labels only.

Offline verification: 271 HTTPS lifecycle/orchestration tests passed, including
14 dedicated v4 cases and enabled/disabled v4 child-flag/migration checks.
The proxy suite passed 38 tests, including exact-route, legacy import denial, byte-preserving stream forwarding
and capability refusal. The legacy-route regression failed before the scoped fix.
Mocks are not runtime acceptance. Recovery acknowledgement-loss fault injection is now source-prepared separately
below, but was not exercised by the enabled-route acceptance run.

## HTTPS acceptance

The approved backend build and single enabled-route HTTPS run completed using
existing dependencies, PostgreSQL image and localhost TLS. Evidence is retained
in `.local/asset-client-903a0dd244b1780eeef59c1a232cce5f/result.json`.
The real Dart client confirmed two-account isolation, exact replay, session/account
binding, complete reexport and date/location/manual-check-date preservation and
content conflicts. Negative HTTP cases returned the expected 401/403/400/413
without changing asset/receipt counts.

Independent inspection confirmed the matching ownership label, stopped container,
and closed loopback ports 29951/29952/29953. Synthetic container/volume and evidence
were retained. No retry, regular-backend change or native app launch occurred.
Disabled-route 404 mode remains offline-tested only; it was not run in this
single enabled-route fixture. Recovery fault injection and native UI remain pending.
Do not run this driver against a regular backend or infer approval to do so.

## Broad offline regression

The full backend default Jest run completed with 974 passing tests and 111
opt-in tests skipped (73 passing suites, 21 skipped). The full Flutter default
suite completed with 1,099 passing tests and one skipped test. These runs include
older feature contracts, but skipped cases do not count as acceptance. Neither
command built or started a product backend, Docker fixture or Windows app.

## Recovery HTTPS source plan

`scripts/recovery-v4-https-fixture.py` reuses the owned lifecycle and existing
candidate requirements. Prepare saves a private v4 file; a test-only proxy drops
one complete successful v4 response for the selected key. Separate Dart processes
submit and reconstruct/replay the exact operation. The harness independently
checks envelope SHA-256, endpoint/account/schema/key binding, committed row/receipt
counts, and byte-identical SQL snapshots before/after replay. The driver checks
manual check dates as well as base fields, dates and location.

Fault injection is opt-in through the dedicated recovery CLI only; ordinary CLI
cannot accept a fault key. Legacy routes cannot claim a v4 fault. No product
backend code is patched and no automatic write retry is introduced.

Source validation passed 15 recovery orchestration tests, 49 combined proxy/fault
tests and three Dart driver tests; analyzer reported no issues. Full HTTPS
orchestration regression passed 286 tests. These are offline results, not proof
of recovery across real HTTPS processes.

Execution requires a new approval for one synthetic recovery HTTPS fixture using
the existing backend candidate, no retry. Keep the stopped owned container/volume,
private synthetic recovery file and reports. Do not alter regular backend data,
TLS trust, firewall or Windows security. Native acceptance remains separate.

## Recovery HTTPS acceptance

The approved single run using the existing candidate completed successfully.
Evidence remains in
`.local/asset-client-d40574a11d725509cc5e859611534ef3/result.json`.
The selected successful reply was suppressed after the backend committed; a fresh
Dart process verified the private recovery file and replayed the same request.
Asset/receipt snapshots remained byte-identical. Base fields, dates, location and
manual check date were retained, and the reconstructed operation returned the
original record identity rather than creating another asset.

Independent inspection confirmed the matching ownership label, stopped container
and closed ports 29961/29962/29963. Container, volume, private synthetic recovery
file and reports were retained. No build, retry, regular-backend change or native
app launch occurred in this run. Native dialogs/Windows behavior, Codacy coverage
and commit approval remain separate pending gates.

## Windows session preparation

The native runner supports the explicit `--import-v4-mode` profile. It requires
an exact release manifest enabling import, import v4, dates, location and manual
check dates; older import versions and export v4 are not prerequisites. The
synthetic file contains one new asset with purchase `2024-02-29`, warranty
`2027-02-28`, location `Synthetic room %_1` and check date `2024-03-01`.

Offline native-runner contracts pass (39 tests). At this source-only checkpoint, no Windows build or native v4
acceptance was claimed; the launch outcome below supersedes build status. A separately approved bounded session must verify saving
private recovery, explicit confirmation (two assets), then restoring and replaying
the same request without adding another asset. Existing ownership, manifest,
loopback, no-overwrite and 30-minute guards remain unchanged.

## Windows launch outcome

The approved release build for the isolated port 29973 completed successfully.
The single fixture reached native-session setup, but Code Integrity events 3077
and 3033 identified the exact candidate executable as blocked. No native import,
Save, Cancel or replay acceptance is claimed. No retry or security change occurred.

Evidence is retained in
`.local/asset-client-07c04e48bdede4554dccfd341b9540bc/` (result and
`windows-launch-review.json`). Independent inspection confirmed matching ownership,
a stopped container, no published ports and closed ports 29971/29972/29973.
The candidate, synthetic files and fixture volume remain retained. Native
acceptance and Codacy coverage remain pending, independently of the passing
PostgreSQL and HTTPS recovery fixtures.
