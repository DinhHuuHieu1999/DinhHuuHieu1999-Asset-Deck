# Inventory import v3: location-preserving add-only proposal

Status: pure request/draft/recovery source and offline tests implemented.
Repository/API and Dart client source are also implemented with offline tests.
The isolated PostgreSQL repository fixture passed eight scenarios; a separately
approved normal HTTPS/Dart fixture and response-loss recovery fixture also passed.
The Windows synthetic fixture has scoped operator confirmation for import,
recovery replay, preserved dates/location and chooser Cancel; see the
[UI acceptance record](inventory-import-v3-ui-plan.md). The separately approved disabled-route HTTPS fixture also returned 404 without
changing asset/receipt counts; see the [HTTPS record](inventory-import-v3-https-plan.md).
Codacy and deployment remain unverified. No commit is approved.

## User value

Import a verified export v3 without dropping its manual location or purchase/
warranty dates. Keep existing assets untouched; duplicates remain separate assets.
No discovery, geolocation, team sharing or automatic merge is included.

## Compatibility and write contract

- Keep export/import/recovery v1 and v2 unchanged. Do not silently down-convert v3.
- Use a separate authenticated POST `/api/v1/assets/import/v3`, default disabled.
  Require existing import, dates and location capabilities, but not an enabled
  export route: a file may have been exported elsewhere.
- Accept exactly `requestId` and `records`. Each record contains the five existing
  editable base fields, two explicit nullable dates and explicit nullable location.
  Reject source IDs, versions, timestamps, owner overrides and unknown fields.
- Reuse canonical location validation and strict date/base validation. Owner comes
  only from auth. Keep raw-byte/duplicate-key/Unicode/CSRF/freshness protections.
- Bound each request to 1-500 assets and 1 MiB serialized UTF-8; refuse partial
  batches. Export, request and recovery sizes have independent checks.

## Atomicity and recovery

- Probe migrations 001/002/003/004/005 without applying them at startup. No new
  schema is justified unless implementation review discovers a missing invariant.
- Insert base fields, dates and location in one transaction, with new server UUIDs
  and version 1. Never call follow-up per-record date/location update endpoints.
- Use a schemaVersion 3 canonical digest including nullable location and dates.
  Reuse owner/request uniqueness; same contents replay original ordered IDs;
  changed contents or keys reused across versions conflict without extra inserts.
- Lost commit acknowledgement is unknown, not failed. Preserve the exact request
  identity and bytes in a separately versioned, account/endpoint-bound private
  recovery envelope; no automatic resubmission or replacement request key.
- Disable only the new flag for rollback; retain data/schema/receipts.

## Staged acceptance

1. Pure request/draft/recovery source and offline tests; no runtime or UI changes.
2. Repository/API/client tests; preserve all v1/v2 contracts and defaults.
3. Separately approved PostgreSQL fixture: dates/location, 500/501 bounds,
   replay/conflict/cross-version keys, two owners, concurrency and rollback.
4. Separate HTTPS real-Dart check including CSRF and lost-response recovery.
5. Observe current rendered import UI before a separate opt-in v3 screen change.
   Explicit review and confirmation, clear replay status, no automatic import.
6. Separate Windows fixture and manual acceptance, then scoped commit review.

No production dependency, migration, deploy, push, security-policy change or new
fixture is included in this design step. Codacy exceptions never imply PASS and
must not silently extend from export v3 to this new import scope.

## Pure slice implementation

Backend `prepareAssetImportV3` validates the complete eight-field record shape,
reuses base/date/location validation, freezes normalized records, and hashes a
schemaVersion 3 canonical payload. The separate opt-in route installs a bounded raw JSON parser, reusing the existing
lexical guard for duplicate keys, Unicode and nesting. The pure function itself
does not add a listener.

Dart `AssetImportV3Draft` prepares only from a verified v3 export, strips source
metadata, binds the operation to the current account and retains exact request
bytes/key when restored. `AssetImportV3Recovery` uses schemaVersion 3 and operation
`inventory-add-only-v3`, exact endpoint/account binding, independent 1 MiB request
and 2 MiB recovery limits, and checksum validation. Neither contacts a server or
writes a file. Digest callbacks are injected; stubbed tests validate control flow,
not a SHA-256 implementation. No credentials are included in these envelopes.

No regular backend has been enabled or deployed, and no import UI is added.
Existing v1/v2 implementations remain unchanged. Codacy coverage/exception for the
export phase does not apply automatically to these new files.

## Repository/API and client slice

`ASSET_IMPORT_V3_ENABLED=false` is the template default. Exact `true` requires
`ASSET_IMPORT_ENABLED`, `ASSET_DATES_ENABLED` and `ASSET_LOCATION_ENABLED`; neither
export v3 nor import v2 enablement is required. Bootstrap refuses malformed or
inconsistent configuration before constructing the app. Readiness checks required
asset/date/location columns and receipt columns without migration or data reads.

The route authenticates ownership, rejects query overrides, and uses existing
CSRF/freshness protection with no-store responses. Only POST v3 aliases receive
the larger parser. A repository transaction claims the owner/key receipt and
bulk-inserts all fields together; replay returns stored IDs, conflicts roll back,
and uncertain COMMIT returns a sanitized unavailable outcome without retry.

`AssetImportV3Source` and the explicit Dart method retain exact draft bytes and
check account/session before and after CSRF/response. Malformed receipts remain
uncertain, not definitely-not-sent. Source tests use mocked PostgreSQL and
synthetic loopback HTTP transports, not real product databases or HTTPS.
Further PostgreSQL/HTTPS acceptance needs separate approval. Codacy has not been
run for this slice and no exception is inherited from export v3.

## Repository acceptance harness

The [PostgreSQL fixture plan](inventory-import-v3-fixture-plan.md) defines eight
opt-in scenarios and a mocked offline lifecycle. Source preparation does not
authorize or establish live database acceptance.

## HTTPS harness source

The [HTTPS acceptance plan](inventory-import-v3-https-plan.md) defines a separate
opt-in lifecycle and real Dart driver, including location/date round trips,
conflicts, auth/CSRF rejection and disabled-route checks. Offline tests do not
establish live HTTPS acceptance; execution remains separately gated.

## Recovery harness candidate

The [recovery acceptance plan](inventory-import-v3-recovery-plan.md) reconstructs
an explicit replay from a private file in a fresh Dart process after a test-only
lost acknowledgment. The separately approved isolated fixture passed; see the
plan for observed evidence and remaining acceptance limits.
No UI, native dialog, deployment or commit is included in this candidate.
