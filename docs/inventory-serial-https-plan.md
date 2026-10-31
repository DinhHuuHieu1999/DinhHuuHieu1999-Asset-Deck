# Serial warning HTTPS acceptance plan

Status: source/offline checks, backend build and one approved synthetic HTTPS
fixture passed. Native acceptance and Codacy coverage remain pending.

## Reuse and scope

Reuse the existing `client-https-fixture.py` owned TLS lifecycle and the
`sort-https-fixture.py` pattern. Add a fixed serial wrapper, offline orchestration
tests, a Dart acceptance driver and driver validation tests. Do not introduce a
second proxy, production dependency, migration or configurable arbitrary command.

## Acceptance

- Validate the synthetic marker before registration or authenticated requests.
- Exercise unauthenticated rejection and authenticated DTO validation, including
  repeated/nested values, invalid exclusion UUID, excessive length and NUL.
- Assert `Cache-Control: no-store` and the exact boolean-only response shape.
- Use two synthetic accounts and the real Dart client to verify literal `%`/`_`,
  case sensitivity, blank serial, own-ID exclusion and foreign-ID isolation.
- Put the matched serial beyond the first page and verify it is still found.
- Compare both inventories before/after read checks; duplicate create/update
  must remain allowed. Do not claim that an advisory read reserves uniqueness.
- Preserve the existing transport timeout/session tests; do not add retries or
  weaken default TLS validation to force fixture success.

## Boundaries

Offline tests must prove missing files refuse before shared lifecycle side effects,
only the fixed Dart driver runs once, incomplete/malformed output fails closed,
and source changes invalidate acceptance. No subprocess/network in offline tests.
A later separately approved live run must use a reviewed backend candidate,
existing immutable PostgreSQL image, fresh owned synthetic resources, loopback
ports and existing localhost TLS material. Never read TLS keys in test output,
change trust/firewall/SAC, access regular data or upload evidence. Owned resources
are stopped and retained; no automatic retry. Native acceptance remains separate.

## Offline evidence

Six Python orchestration tests and three Dart driver tests passed. The latter
verify complete bounded snapshots, metadata mutation detection, runaway paging
refusal and rejection of non-fixture endpoints. Eleven existing serial
parser/editor tests also passed. Dart driver analysis completed successfully.
These tests use mocks, not HTTPS or PostgreSQL, and do not prove live auth.

## Live acceptance

One separately approved HTTPS run completed with the real Dart client and two
synthetic accounts. It exercised unauthenticated rejection, invalid query DTOs,
no-store responses, literal/case-sensitive checks, own/foreign ID exclusion,
full-inventory lookup, unchanged read snapshots and duplicate writes remaining
allowed. Owned processes/container were stopped; fixture data was retained.
No retry or regular backend/database change was performed. This is not Windows
native acceptance or evidence of Codacy/security coverage.
