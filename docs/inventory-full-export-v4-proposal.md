# Full inventory export v4

## Scope

Separate opt-in full inventory export includes the public v3 fields plus nullable
`lastCheckedDate`, matching selection v2 naming. Dates are exact Gregorian
`YYYY-MM-DD` values (0001 through 9999), not timestamps. Null means Unknown.
Export preserves stored values; it never infers today or changes check dates.
Existing full export v1-v3, selection v1-v2 and import schemas remain unchanged.
V4 is not accepted by existing import parsers.

## Backend and client contract

`GET /api/v1/assets/export/v4` requires authentication, derives owner from the
session, rejects all query parameters and returns `Cache-Control: no-store`.
A single owner-scoped SQL statement reads base fields, dates, location and manual
check date with a deterministic updated-at/id order. It reads at most 501 rows
and refuses more than 500; the complete final envelope must fit 1 MiB. No partial
export or pagination merge is permitted. Internal owner/check-version fields
are excluded by public-field projection.

The four-field envelope uses `asset-desk-inventory`, `schemaVersion: 4`, exact
serialized `payload` and its UTF-8 SHA-256. Payload contains `exportedAt`,
`complete: true`, matching `recordCount` and `records`. Client parsing rejects
extra/missing fields, duplicate JSON keys/identities, malformed calendar dates,
checksum mismatch and size/count overflow. Records are immutable. Session epoch
is checked before transport and after asynchronous parsing/digest.

`ASSET_EXPORT_V4_ENABLED=false` is the default. Enabling requires the existing
`ASSET_DATES_ENABLED`, `ASSET_LOCATION_ENABLED` and `ASSET_CHECK_ENABLED` flags.
Readiness checks existing columns only; no migration or dependency is added.

## Acceptance and remaining work

Source verification passed 878 backend tests (99 opt-in cases skipped) and
1,063 Flutter tests (one skipped), plus five dedicated native-channel contract
tests. Flutter analyzer reported no issues. These counts describe local source
checks, not runtime acceptance. Checks cover serializer, mocked SQL, synthetic HTTP auth/query/
no-store behavior, strict Dart parser and client session behavior, plus v3
regressions. Mocked persistence does not certify actual PostgreSQL snapshots.
A separately approved PostgreSQL fixture passed all four scenarios, including
two-owner isolation, the 500/501 boundary and concurrent-edit snapshot consistency.
The owned container was verified stopped. A separately approved real Dart HTTPS
run also passed with 51 records, two owners and exact manual date preservation;
its resources were verified stopped afterward. No fixture, database operation or deployment is implied.

Prepare/Save/read-only Inspect UI is implemented behind the default-off
`ASSET_DESK_ENABLE_EXPORT_V4` client flag and requires date, location and check
capabilities. Cancel preserves the preview and checksum; invalid input clears
both. Synthetic renders were inspected at 200% text scaling after capturing the
existing UI baseline. These checks do not certify native dialogs or real HTTPS.
The scoped Windows operator checks passed; broader accessibility and Codacy
analysis remain pending. Sensitive plaintext exports
are neither encrypted backups nor proof of authenticity. No import v4 is planned
in this phase; no commit/push or production rollout is authorized.

## Repository fixture preparation

The [isolated PostgreSQL plan](inventory-full-export-v4-fixture-plan.md) defines
four opt-in scenarios. All four passed in the separately approved synthetic
PostgreSQL run; lifecycle cleanup and an independent inspection confirmed the
owned container stopped. This does not certify HTTPS or native acceptance.

## HTTPS preparation

The [HTTPS client plan](inventory-full-export-v4-https-plan.md) and source harness
passed offline review and a separately approved backend build/real Dart HTTPS
run. Windows dialogs are not covered by that run; later scoped operator results
are recorded in the native plan.

## Native preparation

The [Windows acceptance plan](inventory-full-export-v4-native-plan.md) describes
the separate build/session approval boundary. Launcher flags, seed selection and
handoff have offline coverage. A separately approved Windows candidate was built
and opened; see the native plan for confirmed checks and remaining acceptance
and lifecycle limitations.
