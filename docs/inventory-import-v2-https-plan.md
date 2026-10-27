# Inventory import v2 HTTPS acceptance plan

## Scope

Source-only harness for the actual Dart client against an isolated synthetic HTTPS
backend. This plan does not authorize execution, TLS reads, builds or deployment.

## Prerequisites

- Existing PostgreSQL image pinned by immutable ID; no pull.
- Built backend candidate with import v2 artifacts and migrations 001–004.
- Existing Dart SDK/package cache and localhost certificate; normal TLS validation.
- Three distinct loopback ports, dedicated container/volume and synthetic accounts.

## Checks

The dedicated runner is `scripts/import-v2-https-fixture.py`. Its fixed profile
explicitly enables import, dates and import v2 only in the child backend. Default
and legacy profiles do not enable v2. Missing sources/artifacts fail before Docker.

The Dart driver verifies the fixture marker before registering two accounts. It
exports v2, imports into the other account, checks exact replay, preserves both
dates and version 1, rejects a date-only conflict and checks owner/session binding.
Python independently checks the export SHA-256. Negative HTTP cases cover missing
authentication, missing CSRF, empty/extra-owner/malformed input and oversized body;
asset and receipt counts must remain unchanged.

## Execution boundary

A future separately approved run uses an existing candidate, one bounded fixture
and no retry. No regular database, operator account, trust/firewall or Windows
security setting is changed. Cleanup verifies ownership, stops resources and keeps
the volume/evidence. No credentials or response bodies belong in committed logs.

## Current evidence

Offline checks: 20 shared lifecycle tests, 12 v1 orchestration tests, 12 v2
orchestration tests and 27 stream-only proxy tests pass. These use mocks/synthetic
files and do not certify HTTPS runtime acceptance. Native UI remains outside scope.

## Observed HTTPS acceptance

One separately approved run completed on 2026-10-27 after a normal backend build.
The actual Dart client passed date preservation, exact replay, date-only conflict,
two-owner isolation and session invalidation. All negative HTTP checks passed;
asset/receipt counts remained unchanged during rejection checks. No retry occurred.
Ownership was independently inspected and the fixture container was stopped.
Evidence is retained locally under fixture ID `77beab1738b01f21725268f49fc5b2c5`.
This does not certify native UI, restart/recovery or deployment acceptance.

## Extended harness work (not yet executed)

The current candidate additionally requires a complete verified post-import v2
export matching all editable fields, dates, new IDs and initial version. Offline
regressions reject dropped/changed fields and dates. Negative requests now include
an invalid leap date, an omitted date key and raw duplicate JSON keys. These new
assertions have not been run against HTTPS; the earlier observed fixture must not
be treated as evidence for them. Disabled-route/alias/backend-bound checks and
fresh-process recovery remain implementation work in progress.

## Fresh-process recovery candidate

`scripts/recovery-v2-https-fixture.py` prepares a private synthetic recovery file,
starts a distinct Dart process to submit through the one-shot v2 response-loss
proxy, then starts another process to parse that file and explicitly replay the
same operation. The harness requires a confirmed fault marker, committed asset
and receipt counts, and byte-identical database row snapshots across replay.
The Dart replay additionally compares both dates and version before/after.

Offline evidence: eight orchestration tests and three driver file/argument tests
pass. These are not live recovery acceptance. The runner has not been executed;
no TLS material, database or backend was accessed for this source-only slice.

## Disabled-route candidate

The dedicated import v2 runner accepts `--disabled-v2-route` only with its fixed
v2 profile. The proxy still forwards the exact v2 route; only the backend v2 flag
is false (import/dates stay enabled). After marker verification and synthetic
registration, an authenticated CSRF-protected POST must return 404 without changing
asset/receipt counts. This profile never invokes the Dart import driver. Offline
checks cover profile flags, forwarding selection and the expected HTTP sequence;
actual disabled-route acceptance remains pending.

Current focused offline totals: 21 shared lifecycle tests, 14 import v2
orchestration tests, 13 recovery v2 orchestration tests, 35 proxy/fault tests and
five Flutter driver tests. Parser component tests additionally verify exact 1 MiB,
one-byte overflow and duplicate keys on ordinary/framework aliases. Those parser
tests are not end-to-end HTTPS alias acceptance.

## Extended fixture acceptance (2026-10-27)

Three separately approved runs completed once each, without retry, using the
manifested existing backend candidate:

| Profile                | Fixture ID                         | Observed result                                                                                           |
| ---------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Import/re-export       | `5a2f72b1de50e1963de1188788a8f8c9` | Full editable-field/date comparison, fresh IDs/version, replay/conflict and nine negative requests passed |
| Disabled route         | `e0bd65bb8afb5088b0e0f9f27065d971` | Authenticated CSRF-protected POST returned 404 through forwarding proxy; counts unchanged                 |
| Fresh-process recovery | `ae013c3037c27a79e37f4f36567bbf37` | Confirmed lost success response, new-process file reconstruction/replay; database snapshots unchanged     |

All three results report completed/stopped; Docker independently reported each
container Exited (0). Owned volumes and evidence remain local. No normal backend,
trust/firewall/SAC setting or real account was changed. Earlier pending statements
above describe the source-only checkpoints, not the status of these three profiles.
Native UI and end-to-end HTTPS alias/raw-backend boundary coverage are still not
certified by these runs; parser component evidence remains separate.
