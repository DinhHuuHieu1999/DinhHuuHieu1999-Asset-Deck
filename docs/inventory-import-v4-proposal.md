# Add-only inventory import v4

## Scope and compatibility

Accept full inventory export v4 through a separate explicit flow. Preserve base
fields, purchase/warranty dates, location and nullable `lastCheckedDate`. Existing
v1-v3 and selection contracts remain unchanged; selection files are not imports.
No production dependency or schema migration is planned. Implementation is not
runtime acceptance or deployment approval.

## Request and transaction

Use an independently default-off v4 capability requiring dates, location and
manual check support. The request contains only a request ID and storage records;
source identities, owners, versions and timestamps are never reused. Validate
exact fields, calendar dates, UTF-8, duplicate keys, 500 records and a 1 MiB body.
Keep manual dates literal and nullable; never infer today. Unlike manual editing, snapshot import validates calendar labels without a
current-day cutoff: exact stored dates must survive clock differences and replay.
It never marks an asset as checked today. Repository tests must verify this
separate restoration policy before runtime acceptance.

Canonical request digests include a v4 domain separator and every stored field.
Create fresh IDs and insert assets and the owner-bound receipt atomically. Same
owner/key/digest replays the durable receipt; different content conflicts. A lost
commit acknowledgement is uncertain delivery, never automatic retry. Existing
assets are never updated or replaced; matching serials are not deduplication.

## Client and recovery

Verify the full export checksum before producing an immutable target-bound
preview. Explicit confirmation is required to submit. A private recovery file
binds schema, operation, endpoint, account and exact request/key. Restore checks
integrity and bindings before explicit replay; it does not submit on file open.
Picker Cancel preserves preview; a selected invalid file clears stale evidence.
Plaintext files are sensitive, not encrypted backups or proof of authenticity.

## Verification sequence

1. Pure preparation/parser tests: exact fields, dates/nulls, digest separation,
   all-field sensitivity, limits, immutability and old-version regression.
2. Repository/API/client offline tests: owner isolation, atomic rollback,
   replay/conflict, concurrency, response loss and disabled capability.
3. Capture current UI before changes, then inspect synthetic render and tests.
4. Separate approvals for PostgreSQL, HTTPS/recovery and Windows sessions.
5. Review exact file hashes, Codacy coverage and commit separately. No push.

Historical source-only checkpoint: pure v4 preparation is implemented; 39 v3/v4 preparation tests pass.
The separate repository includes manual dates in the receipt transaction; mocked
v3/v4 regressions pass 134 tests (eight PostgreSQL opt-in cases skipped).
API/parser/module startup wiring is implemented behind
`ASSET_IMPORT_V4_ENABLED=false`, requiring import, dates, location and check flags.
The bounded parser runs before framework initialization, as for older versions.
Scoped v3/v4 regressions pass 172 tests; eight opt-in PostgreSQL cases are skipped.
Dart draft/recovery and explicit HTTP submission are implemented. Scoped Dart
preparation/API tests pass 18 cases, including old-v3 API regression; requests
retain exact bytes and session/account binding, with no automatic retry.
At that checkpoint, persistence, recovery transport and UI were not yet verified.
The current fixture and native status below supersedes this historical checkpoint.

## Additional recovery checks

Fourteen dedicated Dart recovery boundary tests pass, covering account/endpoint
binding, malformed Unicode, duplicate keys, separate request/recovery size bounds,
500 records and exact whitespace retention. These use a digest stub and do not
certify SHA-256 or disk/HTTPS behavior. The current v4 backend suite passes 81
tests, including conflict when only the manual check date changes.

## Repository harness readiness

The [PostgreSQL fixture plan](inventory-import-v4-fixture-plan.md) and runner are
prepared. All 106 shared PostgreSQL lifecycle tests pass offline with mocked
commands, including seven v4 cases. The live v4 suite contains eight scenarios
and remains opt-in; no v4 database run is implied by these offline results.

## UI source progress

The standalone v4 review page now retains the v3 workflow: bounded file selection,
explicit private recovery save, account confirmation and one operation key.
It displays nullable `Last checked date` alongside dates/location. Session changes
invalidate late results; uncertain submission permits only explicit same-key replay.
The existing native recovery methods are reused without adding filesystem paths.

Thirty operation/channel-mock/widget/render tests passed. Existing v3 baseline
captures were inspected at 390/768/1440 pixels with 200% text before implementation;
v4 uncertain/replay captures use the same sizes. System-font synthetic captures
lack some icon/Unicode glyphs, so they do not certify native typography or keyboard
and screen-reader behavior. Inventory/app navigation is now wired through the separate default-off
`ASSET_DESK_ENABLE_IMPORT_V4` flag with import/dates/location/check prerequisites.
Nineteen navigation/render tests (including legacy v3 regression) passed; app
forwarding, signed-out and missing-capability cases are included. No export flag
or older version flag is required. Native Windows acceptance remains pending.

## Current review status

The repository fixture, enabled-route HTTPS fixture and lost-acknowledgement
recovery HTTPS fixture completed successfully. Evidence paths, retained resources
and limitations are recorded in the [fixture plan](inventory-import-v4-fixture-plan.md).
These results supersede the source-only readiness notes above; they do not certify
native dialogs or product deployment.

The Windows runner now supports import v4 with exact feature-manifest checks and
an inert synthetic v4 snapshot. Its 39 offline tests pass. The approved Windows release build passed, but Code Integrity blocked the
executable during the single native fixture. Native acceptance remains pending;
no retry or security change was performed. Codacy coverage and
commit review also remain pending; no security PASS or commit approval is implied.
