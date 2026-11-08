# Add-only inventory import v2: date-preserving design

Status: backend, Dart transport/recovery and separate opt-in v2 UI are implemented
locally. Repository/API and Dart transport passed separately approved PostgreSQL
and HTTPS fixtures; UI passed offline widget tests and synthetic render inspection.
See the [UI evidence and limits](inventory-import-v2-ui-plan.md). Historical phase
results below describe the state at each checkpoint, not current missing work.
No migration, fixture, dependency, build, commit or deployment is authorized by
this document. Windows native acceptance
for recent phases remains pending and is not inherited by this proposal.

## Goal and compatibility

Import a complete verified [inventory export v2](inventory-export-v2.md) without
losing purchase/warranty dates. Add new assets only; never merge by source ID,
name or serial, replace an existing asset, or change another owner's records.
Repeated labels/serials remain separate records. Preserve the v1 export, import,
request digest, receipts and [recovery format](inventory-import-recovery-proposal.md)
byte/semantic contracts. Never silently convert v2 into v1 or discard its dates.

## Proposed capability and API

- Add `ASSET_IMPORT_V2_ENABLED`, default false with exact-boolean parsing.
  Enabling requires both existing import and dates capabilities; fail startup
  for an inconsistent enabled configuration rather than exposing a partial route.
- Register authenticated `POST /api/v1/assets/import/v2` only when enabled.
  CSRF, request freshness, no-store responses and sanitized errors still apply.
  Owner comes only from the authenticated account; refuse query overrides.
- Startup probes existing asset/date columns and receipts from migrations
  001/002/003/004. No new schema is currently justified. Never migrate on startup.
- Client navigation requires explicit import-v2 opt-in, date support and a
  session/source with v2 capability. Legacy stores must remain usable.
- Rollback disables only v2 while retaining assets, date columns and receipts.
  Do not automatically drop schema, delete inserted assets or alter v1 flags.

## Request and calendar contract

The request has exactly `requestId` and `records`. Each record has exactly seven
editable keys: `name`, `category`, `serial`, `status`, `notes`, `purchasedOn`,
`warrantyExpiresOn`. Both date keys must be present and may be null or strict
Gregorian YYYY-MM-DD in 0001-01-01 through 9999-12-31. When both are known,
warranty end must not precede purchase. No timezone conversion or date inference.

Source IDs, account/owner, timestamps, versions, client digest and export envelope
are forbidden in the write request. Generate fresh server UUIDs and version 1.
Use existing base-field validation/edge normalization; validate dates without
trimming, coercing, accepting timestamps or rolling invalid dates forward.

Require 1-500 records and at most 1 MiB exact serialized UTF-8 request, with no
partial batch. Enforce raw bytes before decoding and reject compression, malformed
Unicode, duplicate keys and unknown fields. Cover framework case/trailing-slash
aliases without widening parser limits on unrelated methods or routes. Keep v1
parser behavior unchanged. Export validity does not guarantee the prepared request
or recovery envelope fits its independent byte limit; refuse before submission.

## Atomic insertion and replay

Validate/freeze the entire batch before acquiring a connection. Canonical digest:
SHA-256 over a fixed-key-order normalized records payload with format
`asset-desk-inventory-add-only` and schemaVersion 2. Include both explicit nullable
dates; record order matters, input property order and request ID do not. Keep the
existing v1 canonicalization unchanged. Date changes must change the v2 digest.

Reuse the owner/request UUID unique claim in `assets.import_receipts`. Same owner,
key and normalized v2 contents return the original ordered IDs without inserting.
Changed contents or reuse of the key across v1/v2 conflicts (409), even if base
fields match, because canonical digests are version-separated. Different owners
have independent keys and never receive one another's receipts.

Use one connection and transaction to claim the receipt and bulk-insert base fields
and dates together. No follow-up per-record date updates: they risk partial writes
and version increments. Preserve existing READ COMMITTED conflict serialization,
row-count/receipt checks, rollback and broken-connection handling. Lost COMMIT
acknowledgment is uncertain, never a reason to mint another key or auto-retry.
Receipt loss/database rollback can invalidate replay protection; do not promise
unconditional exactly-once delivery or treat export JSON as a database backup.

## Review and private recovery v2

Use separate immutable draft/recovery models, not a widened v1 decoder. Verify
export checksum over exact payload UTF-8 and validate all v2 records before
preparing a new UUID v4 operation. Display target account, count, operation key,
base fields and both dates (including an explicit unknown/null label).

Require a saved private recovery file, then a fresh acknowledgement and explicit
confirmation. Cancel/save failure does not submit. Prevent double confirmation;
account/session/source/file changes invalidate review. Unsent Back offers
Keep/Discard; an uncertain operation retains its original exact request for manual
replay and blocks replacing it with a newly keyed draft.

Recovery uses format `asset-desk-import-recovery`, envelope schemaVersion 2.
Its exact payload keys are `apiBase`, `accountId`, `operation`, `requestJson`;
`operation` must equal `inventory-add-only-v2`. Hash exact payload bytes. Bind the
current configured API base/account and fixed v2 operation before actionable
review; never contact a file-supplied endpoint or restore credentials. Preserve
exact request JSON/key across processes, not a reserialized or new operation.

Retain the existing 2 MiB file bound (including escaped envelope), strict JSON,
checksum, UTF-8 and native no-overwrite behavior. Files contain sensitive plaintext;
checksum is not authenticity/encryption. A reopened saved operation is always
outcome-unknown even if never submitted. Selecting a file performs no write.
V1 readers refuse v2; v2 readers refuse v1 or offer a separate explicit v1 flow,
never a fallback. Keep recovery files after success; no automatic deletion.

## Implementation slices and evidence required

1. Pure server/client normalization, version-separated digest and immutable codecs.
   Red/green tests for seven exact fields, dates/order/leap/year bounds, Unicode,
   duplicate/unknown keys, count/byte limits and no v1 behavior drift.
2. Source-only repository/controller/config/parser wiring and tests: three-flag
   readiness, auth/CSRF/query rejection, one bulk insert and rollback, same-key
   replay/conflict, cross-version conflict and sanitized uncertain outcomes.
3. Inspect current UI renders before editing; implement review/recovery with
   source tests, 390/768/1440 captures at 200% text and session/late-result guards.
4. Separately approved PostgreSQL fixture: 500 dated/null records, two owners,
   identical/conflicting concurrency, v1/v2 same-key races, row failure rollback,
   lost COMMIT acknowledgment and exact replay. Retain stopped owned resources.
5. Separately approved real Dart HTTPS fixture: marker/TLS validation, disabled
   route, auth/CSRF/aliases/raw bounds, date-preserving import then complete v2
   export, unchanged existing rows, process-loss recovery and explicit replay.
6. Native file/dialog, cancel, Keep/Discard, save/restore and post-login review
   acceptance require separate Windows execution approval. Preserve SAC/trust;
   never infer native PASS from build, widget tests or HTTPS.
7. Review scoped files and analyzer coverage before requesting local commit.
   Unsupported/unavailable analysis remains explicit, not security PASS. Commit,
   push, regular deployment and recovery drills each retain their own approvals.

## Design review references

The existing receipt primary key is `(owner_id, request_id)` and stores a digest
plus ordered UUID array; it can represent v2 without schema expansion if the
version-separated conflict tests pass. Migration 004 already defines nullable
date range/order constraints. Existing v1 code inserts five fields and its parser
matches only the original import route; neither can be assumed to support v2.
These observations justify the proposed reuse, not implementation acceptance.

## Pure codec verification

The separate backend v2 preparer reuses existing base-field and calendar validation,
freezes all records, and hashes a schema-version-separated canonical payload.
The existing v1 preparer is unchanged. This object-level helper cannot detect
JSON duplicate keys already lost during decoding: raw transport/parser integration
is still required before exposing an endpoint.

Dart v2 draft/recovery models retain all seven reviewed fields, exact request JSON
and request UUID. Recovery binds the API base, account and fixed v2 operation;
strict bounded decoding rejects duplicate keys and malformed Unicode. Checksums
are integrity checks, not authentication. No network or disk I/O occurs in codecs.

Offline verification: backend typecheck and 57 focused tests passed; Flutter
analyzer and 86 focused v1/v2 export/import/recovery tests passed. Digest callbacks
in Dart tests are controlled stubs, not independent SHA-256 interoperability proof.
Endpoint, SQL atomicity/replay, real digest interoperability and Windows native
acceptance remain unverified for import v2. No fixture or deployment was run.

Broader offline regression also passed: 353 backend tests (34 opt-in tests
skipped) and 484 Flutter tests (one opt-in test skipped). Boundary tests verify
an exactly 1 MiB seven-field request is accepted and one extra UTF-8 byte is
rejected, record ordering affects the digest, and either date affects the digest.
These results do not authorize or demonstrate endpoint integration.

## API integration in progress

Local source now contains a separate opt-in v2 controller, module, repository and
raw JSON parser. `ASSET_IMPORT_V2_ENABLED=false` by default; enabling requires
both `ASSET_IMPORT_ENABLED=true` and `ASSET_DATES_ENABLED=true`. Startup probes
existing date/receipt columns and never applies migrations. The write route is
`POST /api/v1/assets/import/v2`; the v1 route/parser remain unchanged.

Repository mocks pass 24 v2 tests (47 alongside v1), including dates in the same
insert/receipt transaction without a separate update. Parser/config tests pass
20 cases including duplicate/escaped duplicate keys, malformed Unicode/raw UTF-8,
compression and exact route scope. Controller/module/bootstrap focused tests
passed before the additional parser tests. These are synthetic source contracts,
not PostgreSQL/HTTPS acceptance. Dart transport now exposes a separate `importInventoryV2` capability and validates
a v2 receipt before reporting success. It sends the exact retained JSON bytes,
including whitespace, after account/session and CSRF checks; it never retries
internally. Focused transport/codec tests passed 26 cases, including v1 regression.
Flutter analyzer passed. Bootstrap tests passed 11 cases including all-three-flags
registration and fail-closed inconsistent v2 configuration.

Final source-only regression after transport wiring: backend typecheck and 411
tests passed (34 opt-in tests skipped); Flutter analyzer and 489 tests passed
(one opt-in test skipped). A synthetic 503 response leaves the exact operation
unchanged and produces one request only. Codacy reconnected and returned no
findings for the added transport regression; that is not a coverage/security PASS.
No PostgreSQL, HTTPS product fixture, native build or deployment ran in this slice.

The subsequently approved [isolated repository fixture](inventory-import-v2-fixture-plan.md)
passed all eight PostgreSQL scenarios on 2026-10-27, including real transactions,
date retention, cross-version conflicts and lost-COMMIT replay. The owned
container was stopped and its volume retained. HTTPS/client/native acceptance,
UI integration, backup/restore and deployment remain outside this evidence.

## HTTPS evidence and remaining gates

The separately approved [HTTPS fixture](inventory-import-v2-https-plan.md) completed
on 2026-10-27 using the actual Dart client and normal certificate validation.
It proves date-preserving insertion, exact replay, date-only conflict, independent
owner keys, account/session guards and the listed negative HTTP cases. It does not
prove every requirement in implementation slice 5: disabled-route HTTP behavior,
transport aliases/raw backend bounds, a complete post-import v2 re-export and
process-loss recovery still require dedicated acceptance evidence.

| Remaining area        | Evidence needed before acceptance                                                     |
| --------------------- | ------------------------------------------------------------------------------------- |
| UI review/recovery    | Inspect baseline renders before changes; implement separate v2 flow and guarded tests |
| HTTPS coverage gaps   | Explicit assertions for disabled route, parser aliases and post-import export         |
| Process-loss recovery | Separate saved-operation/replay scenario with a new Dart process                      |
| Native dialogs        | Separately approved Windows checks; retain pending while blocked by security policy   |
| Local commit          | Selected-file review, analyzer coverage and explicit commit approval                  |

No v2 UI, native acceptance, restart/restore, deployment or complete phase acceptance
is claimed by the passing repository/client fixtures. Existing v1 flows remain
separate; no automatic fallback or date-dropping conversion is acceptable.
