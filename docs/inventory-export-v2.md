# Inventory export v2: purchase and warranty dates

## Scope

Source candidate on `feat/asset-export-dates-v2`; not deployed.
Keep the existing JSON v1 endpoint, schema, import and recovery behavior unchanged.
V2 adds explicit `purchasedOn` and `warrantyExpiresOn` keys to every asset record.
Each value is null or a Gregorian YYYY-MM-DD label, without timezone conversion.
There is no import v2, scheduled reminder or new dependency.

## Backend contract

`GET /api/v1/assets/export/v2` is registered only when the existing dates capability
is enabled (`ASSET_DATES_ENABLED=true`, explicit migration 004 required).
Authentication is required; owner identity comes from the authenticated session.
Query parameters are refused. Responses use `Cache-Control: no-store`.

The envelope retains format `asset-desk-inventory`, with schemaVersion 2,
string payload and SHA-256 over its exact UTF-8 bytes. Payload fields remain
exportedAt, complete, recordCount and records. Records contain the nine v1 public
fields plus both nullable dates; owner/internal columns are never projected.
Limits remain 500 assets and 1 MiB for the serialized envelope, with no partial
success. Full export is independent of list search/status/category/page.

Base fields, shared version and dates come from one owner-scoped SQL statement,
not a list followed by per-record date requests. Statement-level MVCC is intended
to keep concurrent changes from mixing versions within the exported snapshot.
This concurrency behavior passed the isolated PostgreSQL fixture described below.

Exports contain sensitive plaintext serial numbers and notes. Checksums detect
changes, not authenticity. JSON is not an encrypted database backup.

## Dart source acceptance

`AssetExportV2` is a separate immutable model. It requires exactly the v2 envelope
and eleven public record fields, explicit nullable dates, valid Gregorian labels
and date ordering, unique identities, complete count and the existing bounds.
The bounded JSON guard rejects duplicate keys before SDK decoding. SHA-256 uses
the exact original payload UTF-8 bytes, not a reserialized payload.

`AssetApi.exportInventoryV2` uses the authenticated dedicated route, with session
checks before and after native checksum work. It never falls back to v1, retries
or accepts prepared private data after sign-out. Existing v1 parsing/import and
recovery paths are unchanged. Digest callbacks in unit tests are mocks, not proof
of native cryptography.

The three targeted Dart suites passed 122 tests. Backend typecheck and all 260
backend unit tests passed. The final default run skipped 23 opt-in SQL cases;
four v2 SQL cases were separately executed below. SQL concurrency and HTTPS
transport passed isolated fixtures; native v2 acceptance remains unverified.

## Export UI source acceptance

The inventory page exposes `Export JSON v2 with dates` only when the dates UI
flag is enabled and the store implements the separate v2 export capability.
The original v1 entry and contract remain available and unchanged.
Both versions share the Prepare/Save screen implementation, with explicit v2
labels and the warning that v2 import/restore is unavailable. No request or disk
write occurs merely by opening the screen. Cancel keeps the prepared snapshot;
failed Prepare clears stale output, and save failure does not retry automatically.

The Windows adapter reuses the existing bounded checksum and no-overwrite Save As
channel through a separate typed `saveV2` method; the C++ handler is unchanged.
Mock channel tests check exact v2 bytes, Cancel, malformed results and the existing
file refusal. These are not native dialog or disk-write acceptance.

Baseline and post-change synthetic renders are retained under
`.local/export-v2-ui-20261026-a/`. V2 renders at 390/768/1440 and text 200% passed;
the 390 and 1440 images were visually inspected. V1 PNG bytes at 390 and 1440
match the baseline exactly. The three targeted UI/native-adapter suites passed
28 tests using synthetic sources and mocked platform channels.

## Remaining acceptance and deployment limits

- Keep Windows native acceptance pending while Application Control blocks launch.
- No regular database/backend changes, dependency installation or push.

## Isolated PostgreSQL fixture source

`scripts/export-v2-postgres-fixture.py` opts into a fixed four-scenario suite.
It reuses the bounded lifecycle with an existing immutable image, a new synthetic
database/container/volume, one random loopback-only port, migration 001/002/004
and marker verification. There is no pull, backend startup, retry or deletion.
Cleanup verifies ownership before stopping; resources and evidence are retained.
The overall execution deadline is 120 seconds, with a bounded cleanup window.

The source scenarios cover empty/null/extreme dates, 51 records and two owners
without writes, 501-record refusal, and concurrent committed changes. The latter
uses a test-only advisory barrier in the snapshot statement, observes its actual
lock wait, commits a base/date/version edit and checks old versus subsequent new
snapshots. It does not alter the production snapshot query.
Four mocked runner tests passed, including missing-file preflight for every
required source and fixed profile/identity/env/cleanup checks. Live execution is
not implied by these offline tests; the executed evidence is recorded below.

## Isolated PostgreSQL acceptance

The single run `.local/asset-export-v2-eec9a3ef089b9574742d4a6f551f69a4/`
completed all four scenarios, with zero failed or skipped assertions. The exact
Jest report and lifecycle report are retained. Independent Docker inspection
confirmed the matching fixture ownership label and `State.Running=false`.
The synthetic container and volume remain retained. No regular database/backend
was changed. This establishes SQL repository behavior, not HTTPS transport or
Windows dialog acceptance.

## HTTPS fixture source

`scripts/export-v2-https-fixture.py` selects the existing explicit dates lifecycle,
requires compiled v2 artifacts and fixed Dart/helper source before resources, and
runs the marker-guarded Dart driver once. The test-only proxy permits only exact
GET `/api/v1/assets/export/v2` when dates are enabled. Import stays disabled.
The normal TLS checks remain enabled; existing localhost certificate references
are explicit, without trust/firewall changes.

The driver checks empty export, 51 owned assets, explicit null and extreme dates,
a separate owner's asset, unchanged v1 output, list-filter independence, repeated
read-only output and signed-out refusal. It uses the existing bounded Python
SHA-256 stdin oracle, not a mocked checksum or new production dependency.
Native dialogs are not exercised. The runner accepts only the exact typed result,
and stores only a whitelisted stage on failure, never credentials or response data.
Six offline orchestration tests and 23 proxy tests passed. Flutter analyzer found
no issues. These offline gates preceded the live HTTPS acceptance below.

## HTTPS acceptance

One backend candidate build and the single fixture
`.local/asset-client-f0fd7d8de191c4bc638a3995cf0dd506/` completed successfully.
The exact typed driver result established 51 owned assets, two owners, Python
SHA-256 verification, nullable/extreme dates, v1 preservation, list-filter
independence, unchanged repeated records and signed-out refusal. Default TLS
validation remained enabled. The lifecycle report records completed cleanup;
independent Docker inspection confirmed the matching ownership label and stopped
container. Resources were retained. No normal backend/database, trust, firewall
or Windows security policy changed. Native Save As remains pending.
