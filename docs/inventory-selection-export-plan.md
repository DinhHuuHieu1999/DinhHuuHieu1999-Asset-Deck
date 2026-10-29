# Filtered inventory selection export

Status: source, isolated PostgreSQL/HTTPS and the four functional Windows
checks have passed. Both feature flags default off. Codacy analyzer coverage and
screen-reader acceptance remain unproven; no commit or deployment is implied.

## Contract

The separate `asset-desk-inventory-selection` format, schema version 1, contains
canonical applied filters and public records including dates and location. Existing
full inventory export/import v1/v2/v3 remain unchanged; this selection is not a
full account backup and is not accepted by the existing import flow.

The payload contains `exportedAt`, `scope=filtered-selection`,
`allMatchesIncluded=true`, `filters`, `recordCount` and `records`. It omits the
full-catalog complete marker. SHA-256 covers exact UTF-8 payload bytes, not
authenticity or encryption. Files contain private plaintext.

Limits are 500 records and 1 MiB for the entire envelope. Overflow fails instead
of truncating. One owner-scoped SQL statement evaluates literal search, status,
category, location and optional warranty predicates before deterministic sorting
and the 501-row overflow sentinel. No page concatenation or owner metadata.
Warranty filters require an explicit reference date.

## Integration

Backend `ASSET_SELECTION_EXPORT_ENABLED=false` requires date/location flags and
existing migrations 001, 002, 004 and 005. No migration or dependency is added. The authenticated
GET endpoint rejects unknown, repeated and nested query parameters and sets
`Cache-Control: no-store`.

Flutter `ASSET_DESK_ENABLE_SELECTION_EXPORT=false` additionally requires date and
location UI capabilities. Navigation captures last successfully applied filters,
not draft controls. Prepare is explicit; applied filters are expandable. Save
Cancel preserves the result; failed Prepare clears the prior result/checksum.
Transport checks response scope and the account epoch after checksum verification.

Selection saving uses the fixed native `saveSelectionJson` method and suggests
`asset-desk-inventory-selection.json`. Existing save methods are unchanged.
It reuses the 1 MiB, no-overwrite writer; static contracts do not prove compilation
or native dialog behavior.

## Evidence and remaining checks

- Backend: 47 selection tests and typecheck passed; full suite 678 passed,
  66 opt-in tests skipped. HTTP tests use synthetic auth and mocked SQL.
- Existing export v1/v2/v3 regression: 110 tests passed.
- Selection parser/API tests: 105 passed with synthetic loopback responses.
- Latest save adapter and selection UI group: 29 passed. Native static contracts:
  7 passed; no native build was run.
- Synthetic baseline preceded UI edits. Selection renders at 390/768/1440 width
  and 200 percent text were inspected without observed clipping. Final captures in `.local/selection-export-final` include the final checksum
  wording and were inspected at all three widths; this is not native/a11y acceptance.
- The first full Flutter run had 792 passes, one skipped and one loopback import
  failure. That unchanged import test file passed 5/5 in isolation. A serial full
  rerun is recorded separately; the original failure is not treated as PASS.

The seven PostgreSQL scenarios now verify repository filtering, owner isolation,
limits and concurrent snapshot behavior on synthetic data. HTTPS, native
Save/Cancel, screen reader and Codacy remain unverified. No regular runtime
enablement, commit, push or deployment is claimed. Prior-phase exceptions do not
apply to these changes.

The serial full rerun overlapped the save-method source/test edit and therefore
used mixed revisions (three adapter method-name failures). It is invalid as a
final full-suite gate. The final adapter/UI group passed 29 tests, the subsequent
UI-only run passed 5 tests, and analyzer reported no issues. The subsequent frozen-tree full rerun passed 793 tests with one opt-in skip.
The earlier failed runs remain retained and do not establish a root cause for
the transient loopback failure. Offline success is not runtime acceptance.

## Repository harness source

The [PostgreSQL fixture plan](inventory-selection-export-fixture-plan.md) defines
seven opt-in cases. The fixed runner and profile are implemented; 67 offline
repository-lifecycle regression tests pass (six specific to selection). Backend
typecheck and 19 serializer/repository unit tests pass; the seven live cases are
verified skipped by default. These offline checks preceded the separately approved seven-scenario PostgreSQL
run recorded in the fixture plan.

## Additional offline client evidence

After the earlier full-suite pass, 27 targeted selection parser/widget tests pass,
including sign-out with prepared/pending data and late-response disposal, all
navigation prerequisites, 0/51/500/501 records, UTF-8 envelope overflow, duplicate
payload keys/record IDs and hashing the original payload bytes. Analyzer reports
no issues. Only tests changed in this follow-up; the earlier 793-test full run
predates the additional cases and is not relabeled as a new full-suite result.

Codacy MCP responded for both changed Dart test files with `success=true` and an
empty `result` array. No analyzer completion/coverage was identified, so this is
not a Codacy PASS or a new exception. The follow-up client checks started no fixture resources. PostgreSQL was later
run once under separate approval and passed all seven cases; HTTPS/native remain
pending.

## Functional Windows acceptance

The operator confirmed the matching-assets route prepares exactly one asset,
suggests `asset-desk-inventory-selection.json` and saves successfully. Reopening
the Save dialog and cancelling retains the prepared result. Back retains Search
`Synthetic`, status `stored` and one inventory asset. An earlier ambiguous check
on the full-v3 export route was not counted; the selection route was reconfirmed.

The isolated release candidate and fixture identity are recorded in ignored local
evidence, including `selection-export-review/native-manual-acceptance.json`.
These functional checks do not certify screen-reader behavior, all native errors,
Codacy/security coverage or a regular deployment. See the
[HTTPS plan and execution evidence](inventory-selection-export-https-plan.md).
