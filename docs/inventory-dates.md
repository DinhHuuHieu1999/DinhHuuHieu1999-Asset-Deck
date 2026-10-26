# Purchase and warranty dates

Status: implementation and isolated SQL/HTTPS verified; regular deployment unchanged.

## Product behavior

Each asset may have an optional purchase date (`purchasedOn`) and optional warranty
end date (`warrantyExpiresOn`). Dates are calendar labels, not timestamps: strict
`YYYY-MM-DD`, years 0001 through 9999, real Gregorian days. Null means unknown.
Either date may exist alone. When both exist, warranty end must not precede
purchase; equality is valid. Future dates are permitted for planned equipment.
No notification, background task, warranty provider lookup or money field is added.

Use a separate read/update date capability instead of adding optional mutation
fields to the existing full-replacement asset input. The date update must submit
both date fields explicitly (null clears) and the asset version last observed.
Existing asset edits must preserve dates; date edits must preserve existing asset
fields. Both operations share the asset version and reject stale updates without
silently overwriting the other editor. Owner isolation applies to every predicate.
A separate capability keeps old list-only client stores compatible.

## Persistence and rollout boundary

Plan an additive migration for two nullable PostgreSQL date columns with a
cross-field ordering constraint. No backfill or destructive down migration.
New source must explicitly verify required schema before serving the date feature;
never silently treat a missing migration as unknown dates. Fixture provisioning
must apply the new migration before testing new endpoints. Source implementation
must not apply migrations to an operator database automatically.

The intended endpoints are authenticated read-only `GET /assets/:id/dates` and
explicit `PUT /assets/:id/dates`, with no-store responses, UUID validation and
normal CSRF/session enforcement. The response includes asset ID, shared version
and both dates. Missing/non-owned reads share the same unavailable response;
stale/missing/non-owned writes share the same conflict response. Do not expose
another owner's dates or tell the client a failed write succeeded.

## Portability boundary

Inventory JSON v1 explicitly projects legacy fields and does not contain these
dates. Keep v1 byte/schema behavior and recovery/import contracts unchanged.
Existing add-only v1 imports create new records with unknown dates and must not
clear dates on existing records. UI must warn that v1 is not a warranty backup.
A complete dates-inclusive export/import format needs a separately versioned
contract; do not label v1 a complete backup after adding these fields.

## Acceptance

- Reject malformed dates, impossible leap days, omitted fields and invalid version.
- Accept nulls, equal dates and leap-year boundaries without timezone conversion.
- Preserve unrelated fields on date edits, dates on legacy edits, and dirty drafts
  on conflict; prevent blind retry after an uncertain mutation.
- Verify two owners, stale shared versions and persistence/recovery in isolated
  PostgreSQL/HTTPS fixtures after explicit execution approval.
- Inspect baseline synthetic UI before changes; exercise optional dates, clearing,
  Keep/Discard, failure retention and 200% text without new dependencies.
- Keep Windows native acceptance pending while its executable remains blocked;
  do not weaken Windows protection or infer native success from headless tests.

## Source integration

`ASSET_DATES_ENABLED` defaults to false; only literal `true` enables the separate
module, and malformed values refuse startup. When enabled, readiness selects both
date columns and fails if migration 004 is absent. No migration is automatic.
The additive SQL and endpoints were exercised only in isolated synthetic fixtures;
no regular database migration or deployment has been performed. Existing list/export/import repositories are unchanged and legacy asset
updates do not assign the new columns. New date updates increment the existing
asset version and timestamp rather than introducing an independent conflict clock.

## Dart client integration

The optional `AssetDatesSource` capability reads and updates dates independently
from `AssetStore`. Requests use the existing authenticated, bounded transport.
Updates send both nullable date fields and the observed shared asset version,
without owner or identity fields in the body. Local invalid values are rejected
before sending; mutation responses must match identity, incremented version and
submitted dates. Conflicts and ambiguous responses are not retried automatically.

Model and synthetic transport tests cover calendar boundaries, clearing, malformed
responses, foreign identity and conflicts. Subsequent isolated SQL/HTTPS and synthetic UI evidence is recorded below.
Windows native acceptance remains pending; runtime flags remain off by default.

## Optional Flutter entry

`ASSET_DESK_ENABLE_ASSET_DATES` defaults to false. Enable it only against a backend
with migration 004 applied and `ASSET_DATES_ENABLED=true`. Each inventory card then
opens a separate dates editor after fetching its current shared version. Saving
refreshes the inventory; failed reads retain the existing list. Keep/Discard
protects unsaved drafts; conflicts and unknown writes block blind resubmission.
The editor explicitly warns that JSON v1 excludes dates.

## Repository fixture source

The fixed `scripts/dates-postgres-fixture.py` profile reuses the owned lifecycle:
existing immutable PostgreSQL image only, new synthetic database/volume/container,
one ephemeral loopback port, a 120-second deadline, no retry and verified stop.
It applies only migrations 001, 002 and 004. Four opt-in repository scenarios cover
owner isolation, legacy/date field preservation and stale versions, concurrent
writes, and database-level date constraints. Default Jest skips these scenarios;
compilation or mocked lifecycle tests do not prove live SQL acceptance.

## Repository acceptance evidence

One isolated PostgreSQL run completed all four repository scenarios with zero
failed or skipped tests. The result and full Jest output are retained under
`.local/asset-dates-8394ae683f6dbd7af9df2cc51fe70be2/`. A separate Docker inspection
confirmed the fixture ownership label and `State.Running=false`; its container
and volume were retained. This verifies migration 004 and repository behavior,
not HTTPS transport, backup/restore or Windows native acceptance. No regular
backend or database was changed.

## HTTPS fixture source

`scripts/dates-https-fixture.py` selects dates explicitly, separately from import.
Preflight requires the compiled dates module and fixed driver sources. The shared
lifecycle applies 001/002/004 to a new synthetic database, sets the child backend
flag, and grants only UUID GET/PUT date routes through the test-only TLS proxy.
The Dart driver checks marker ownership with default TLS validation, two owners,
clearing, shared-version conflicts and legacy edit preservation. Partial driver
output never passes. The initial source checks were offline; see the executed evidence below.

## HTTPS acceptance evidence

A backend candidate build and one dates HTTPS fixture completed successfully.
Evidence is retained under `.local/asset-client-9ce94087f2efdacfbeae84c80dc564af/`.
The real Dart client passed marker-bound TLS, two-owner isolation, nullable date
updates, stale shared-version refusal, legacy field/date preservation, clearing
and signed-out refusal. The lifecycle reported completed cleanup and stopped
its dedicated backend/proxy/container. This is not Windows native acceptance or
a date-aware backup/restore test; database recovery was verified separately below.

## Database recovery fixture source

The dates repository wrapper accepts an explicit `--verify-recovery` option.
After the four SQL scenarios, the fixed helper verifies fixture ownership, saves
a custom PostgreSQL dump without overwriting a file, restarts that container,
and compares all asset columns. It restores into a new database in the same
synthetic container and compares again. The original database and dump remain.
No existing operator database or external backup destination is accepted.
This tests database persistence and dump/restore, not inventory JSON v1 recovery
or disaster recovery after loss of the host/container volume.

The recovery run `.local/asset-dates-7e0ea782919e8ddf98f787fdbc0885d9/` completed
all four repository scenarios, restart and restore comparisons for four assets.
The dump and SHA-256 comparison report remain local. Independent Docker inspection
confirmed the matching ownership label and stopped container. Original/restored
databases and the volume were retained. No operator database was changed.
