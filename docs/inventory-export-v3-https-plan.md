---
title: "Inventory export v3 HTTPS acceptance"
description: "Proposed real Dart client verification without native dialogs."
document_type: "plan"
status: "draft"
audience: ["contributors", "operators"]
---

# Inventory export v3 HTTPS acceptance

The PostgreSQL repository fixture passed. Harness source and offline tests are implemented; one backend candidate build and an approved isolated HTTPS run completed
successfully for v3. Execution requires separate approval.

## Reuse and boundaries

Reuse the existing owned HTTPS lifecycle, TLS proxy and real Dart client pattern
from export v2. Add an explicit export-v3 profile with dates/location prerequisites
and migration 005; do not repurpose import profiles or silently enable v3 in older
fixtures. Keep all feature flags explicit, with v3 off by default.

The source preflight must require the new repository/module/controller artifacts
before resource creation. Retain immutable image, loopback-only ports, ownership
checks, bounded deadlines, no automatic retry and retained stopped resources.
Existing certificate references are allowed only in a separately approved run;
never modify trust, firewall, SAC or regular backend configuration.

## Acceptance requirements

- Anonymous export is refused; authenticated requests use the exact v3 route.
- Empty and 51-record exports are complete, owner-scoped and independent of list
  search/status/category/location filters.
- Preserve exact location (including literal `%` and `_`), null locations and
  calendar dates. Parse the response using the real strict v3 Dart parser.
- Independently calculate SHA-256 over exact UTF-8 payload bytes using the existing
  Python stdin digest bridge. Do not send payloads or credentials to logs.
- Verify a second owner cannot see private records and export does not change
  rows/versions. Reject query parameters and assert `Cache-Control: no-store`.
- Re-check v1/v2 schemas still omit location; do not add import v3.
- Sign-out invalidates the session. A partial/malformed driver report or failed
  stage cannot satisfy acceptance; retain only an allowlisted stage identifier.

Offline tests must use mocked commands/network boundaries and verify fixed
profile/source selection, missing artifacts before side effects, exact typed
result validation, and safe failure reports. No native dialogs are exercised;
Windows save/Inspect acceptance remains separate even if HTTPS passes.

## Source checkpoint

The driver implements two owners, anonymous refusal, empty/51-record exports,
location/date preservation, checksum via the existing Python bridge, legacy
schema preservation, filter independence, unchanged exported rows and sign-out.
The fixture selects a separate v3 profile; old profiles explicitly disable v3.

Six Python orchestration tests and 29 proxy tests pass offline. Dart analyzer
passes. The driver now includes a synthetic raw login, authenticated query rejection
and no-store response-header checks. Its fail-closed status/header validator
passes an offline test; these checks subsequently passed against the approved synthetic HTTPS fixture.
No native dialogs, real TLS or database are exercised by these offline checks.

## HTTPS acceptance

One approved build and real Dart HTTPS fixture passed: two accounts, empty and
51-record exports, location/date preservation, independent payload digest,
anonymous refusal, authenticated query rejection/no-store, older schema
preservation, filter independence, unchanged exported records and sign-out.
The runner completed without retry. Owned container state was independently
verified stopped with the expected ownership label; volume/evidence are retained.

Final offline regression also passed: backend typecheck and 502 tests (50 opt-in
skipped), Flutter 644 tests (one skipped). These counts do not replace live or
native checks. Windows dialogs/Inspect acceptance, Codacy and commit remain
pending; no regular backend or trust configuration was changed.
