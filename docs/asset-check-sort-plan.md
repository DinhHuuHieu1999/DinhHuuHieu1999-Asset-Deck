# Oldest manual check date first

Status: implemented; PostgreSQL, HTTPS/Dart and Windows core-sort checks passed.
Native selection-export interaction and Codacy coverage remain unverified.

## Behavior

The optional list sort `checked_asc` orders known manual dates oldest first,
Unknown dates last, then stable UUID ascending for equal dates. Unknown is not
proof an asset was never inspected; its existing dedicated filter remains the
explicit way to prioritize unknown values. Keep `updated_desc` as the default
and preserve `name_asc` exactly.

Apply sorting in owner-scoped SQL before LIMIT/OFFSET for all inventory route
combinations. Use a fixed SQL fragment `last_checked_on ASC NULLS LAST,id ASC`;
never interpolate arbitrary query text. Require the existing check-date feature
and schema readiness; reject this sort when disabled rather than referencing a
missing column. No date is changed or inferred from updated_at.

Draft selection does not apply until Apply. Refresh, Details/Back, Reset and
all overview drill-downs preserve the last applied sort, not an unapplied draft.
Failed load retains the previous applied list and controls under existing rules.

## Compatibility boundary discovered during review

The shared `ASSET_SORTS`/`assetOrderBy` is also used by selection export v1/v2.
Do not broaden legacy serialized scope enums accidentally. Separate legacy export
sort validation from extended list sort validation. Existing selection versions
must reject the new sort explicitly; disable matching selection export while it
is applied, with a short explanation. Full exports remain unchanged. Supporting
the new sort in a future selection format is outside this slice.

## Verification

- Default/old sorts unchanged; strict new enum and feature-off rejection.
- Owner isolation; ordering before pagination; stable equal-date ties; NULL last.
- Search/status/category/location/warranty/check filter combinations.
- Legacy selection format rejects new sort; old export/Inspect/import unchanged.
- Client query validation, applied/draft state, Reset/Refresh/Back and failure.
- Capture/inspect baseline before UI edits and narrow/wide 200% text afterward.

No migration, dependency, scheduled task, automatic write, fixture execution,
Windows build, commit, push or deployment is authorized by this design.

## Source verification

The shared legacy `ASSET_SORTS` and `assetOrderBy` remain unchanged. Inventory
DTOs and the three list repositories use a separate extended allowlist/helper.
The helper rejects check-date ordering before SQL when check support is disabled.
Existing check-module startup readiness owns the migration 006 prerequisite.

Backend typecheck and 225 focused backend tests passed; 29 opt-in tests skipped.
The focused Flutter run passed 142 tests across API, new sort, existing sort and
selection navigation. Baseline and updated synthetic renders were captured and
inspected at narrow 390px with 200% text; the harness also renders 768/1440px.
System-font test captures lack native icon glyphs and do not certify Windows UI.
Seven focused sort tests passed again after adding Details/Overview Back and
status drill-down preservation. Flutter analyzer reported no issues. No SQL ordering behavior is claimed from mocked query tests.

The selected dropdown label is short; the menu and applied-sort line explicitly
say Unknown last. Matching export stays disabled until a supported sort is
successfully applied, not merely selected as a draft. Full exports are unchanged.
Codacy tools are unavailable in the current runtime, not PASS; no earlier phase
exception covers this change. No fixture, Windows build, commit or deployment
has been performed for this phase.

## PostgreSQL harness (not executed)

The fixed `scripts/check-sort-postgres-fixture.py` profile requires explicit
synthetic opt-in and an existing immutable PostgreSQL image. It reuses the
owned lifecycle, loopback-only port and 120-second deadline; it never pulls an
image or retries. Cleanup verifies ownership, stops the container and retains
the volume/evidence. Missing source is refused before commands or writes.

Four opt-in repository cases cover regular, warranty, exact location and combined
location/warranty lists. They seed 56 matching owner records: 51 equal older
dates (crossing the page boundary), three newer dates and two Unknown values.
They compare the complete ordered IDs across pages, exclude another owner and
a nonmatching record, and compare all rows before/after listing to detect writes.
The suite is skipped by default; offline tests do not prove PostgreSQL behavior.

After harness integration, the full backend default suite passed 984 tests
(115 opt-in tests skipped). All 111 PostgreSQL lifecycle offline tests passed,
including existing profiles; their refusal messages are expected negative-test
output, not evidence of a live fixture run. Typecheck passed. The four new SQL
cases remain unexecuted and require separate operator approval.

The complete Flutter default suite also passed 1,148 tests with one opt-in test
skipped (`test --no-pub`). This remains offline/widget evidence, not native
Windows or live database acceptance.

## Isolated PostgreSQL acceptance

After a sandbox Docker permission refusal before resource creation, the operator
approved one new execution with Docker access. All four repository scenarios
passed against the existing PostgreSQL image with synthetic data. The owned
container was stopped and its volume/evidence retained. No regular database or
backend was changed. HTTPS/client runtime and Windows acceptance remain pending;
this result does not establish them or Codacy coverage.

## Next acceptance: HTTPS and Dart client

Reuse the existing check-date TLS lifecycle with its fixed `check_mode`, not
`location_mode`: location-only setup omits migration 006 and disables the check
feature. Keep existing sort/check drivers unchanged and add a dedicated driver
and fixed wrapper with offline orchestration tests.

The driver must verify the synthetic marker before registration; use two owners
and 56 matching records with old/equal/new/Unknown dates; verify all four list
paths across both pages through the actual Dart client. Include invalid sort
HTTP validation, check-filter combinations and stable ID ties. Verify stored
versions/dates and owner counts after listing, not only response order. Keep
legacy default/name sorts and serialized selection allowlists unchanged.

Preflight must require the new driver, current source and built artifacts before
resource creation. Validate exact typed completion output and hash only public
source/artifacts. Missing sources, malformed output, timeouts or skipped checks
cannot pass. Default TLS verification stays enabled; no trust changes or secret
logging. Offline tests use fake responses/processes only. Build/live execution
requires separate approval; this plan does not authorize either.

The dedicated HTTPS wrapper and Dart driver are now implemented, not executed
live. In addition to four paginated list paths, the driver checks Unknown,
strictly-before and on-or-after filters for each path (12 combinations), including
the equality boundary and filtered pagination. Completion requires exact typed
counts. Offline orchestration tests cover malformed results, missing sources,
fixed check profile, one client execution and source-change refusal.

## HTTPS acceptance

The operator-approved backend build succeeded. One isolated HTTPS run completed
HTTP sort validation and the real Dart client acceptance: 56 matching records,
two owners, four list paths and 12 check-filter combinations. The driver also
verified stored check dates/versions after listing. TLS verification remained
enabled; cleanup stopped owned resources and retained fixture evidence. No
regular backend/database or trust configuration changed. Windows UI and Codacy
coverage remain unverified; no commit or deployment was performed.

## Windows core-sort checks

A no-pub release build and one isolated check-mode native session succeeded. The
operator confirmed saved dates, three-record oldest-first/Unknown-last ordering,
Refresh ignoring an unapplied draft sort, Unknown filtering/Reset and retention
after Details/Overview Back. The app closed and owned resources stopped. These
are operator functional checks, not screen-reader or broad native certification.
Selection-export feature flags were off in this candidate, so its disabled-export
behavior remains widget-tested only. Codacy remains unavailable, not PASS.
