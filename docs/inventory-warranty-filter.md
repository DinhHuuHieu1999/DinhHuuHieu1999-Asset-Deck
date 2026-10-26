# Inventory warranty filtering

Status: source, unit/widget tests and isolated PostgreSQL/HTTPS checks passed.
Windows native acceptance and regular deployment remain pending.

## Product semantics

- Expired: known warranty end strictly before the reference date.
- Expiring within 30 days: known end from the reference date through reference
  date plus 30 calendar days, inclusive. Expiring today belongs here, not expired.
- Null means unknown and never matches either filter.
- A new Apply uses today's UTC calendar date, shown explicitly in the UI.
  Subsequent pages reuse that reference date until Apply/refresh is pressed.
- The horizon saturates at 9999-12-31. Dates remain labels, not local timestamps.
- Search, exact status and category intersect with warranty before pagination.
  Sorting and fixed page size remain unchanged. No client-side page filtering.
- Full export and overview remain independent of list filters.

## Backend contract

A separate list capability under the dates module keeps the old list endpoint
and list-only clients compatible without migration 004. The new endpoint
requires existing dates opt-in and migration readiness, never auto-migrates.
Owner identity must come from authentication, never query input. SQL predicates
must be parameterized and apply before limit/offset. Include the reference date
in the response so pages do not silently shift at UTC midnight. UI controls stay
hidden when the capability is disabled; failed requests retain previous results
with a stale-data notice. Unknown/malformed filter input must fail closed.

Capture and inspect the current rendered inventory before UI edits. Verify
calendar edges, two-owner isolation, more than one page, literal search, null
warranty, same-day boundary and unchanged exports in isolated fixtures before
claiming runtime acceptance. No notification, dependency, new migration, regular
deployment or Windows security change is included.

## Endpoint and pagination

`GET /api/v1/assets/warranty` requires authentication and the existing dates
capability. Query fields are `warranty` (`expired` or `expiring_soon`, required),
`asOf` (optional strict Gregorian YYYY-MM-DD, defaults to current UTC day),
and the existing bounded `q`, `status`, `category`, `offset`. Unknown fields,
including owner input, are rejected by the standard validation pipe. An explicit
reference date is a caller-selected calendar comparison, not a historical data
snapshot or authorization boundary.

The response has `items`, `nextOffset`, `warranty`, `asOf` and `through`.
Each item includes the nine base fields plus nullable purchase/warranty dates.
`through` is the inclusive 30-day horizon, also returned for expired mode but not
used as its cutoff. Dates are projected from the same row read, without N+1.
A single parameterized SQL statement combines owner, literal substring search,
exact status/category and warranty predicates before sorting and LIMIT/OFFSET.
Null dates satisfy neither warranty predicate. Page size stays 50; a 51st row
signals continuation. Traversal past offset 100000 fails with 422, not a silently
complete result. Concurrent edits may still shift offset pages; only the calendar
reference remains stable, not the underlying inventory across requests.

## Verification so far

Backend typecheck and 50 focused calendar/validation/controller/repository-mock
tests passed. They cover leap and century edges, years 0001/0099/9999, UTC day
selection, explicit stable reference, injection-shaped search, invalid input,
authenticated owner propagation, parameter binding and traversal failure. SQL
assertions here inspect text/arguments with a mocked pool; they do not prove
PostgreSQL predicate results, HTTP middleware or two-owner runtime isolation.
Those checks and UI acceptance remain pending. No fixture has run for this phase.

## Dart client boundary

`AssetWarrantySource` is a separate optional capability. `AssetApi.listWarranty`
uses the existing bounded authenticated transport with no retry or fallback.
It validates filters before sending, requires a reference date for subsequent
pages and discards late results on session change. `AssetWarrantyPage` verifies
exact page/record fields, the echoed filter/reference, the computed calendar
horizon, existing base record rules, nullable date validation, unique identities,
page continuation and that every returned warranty satisfies the requested
predicate. Returned collections are immutable. A mismatching response is an
explicit failure, not an empty or legacy list.

Flutter analyzer and 90 targeted parser/transport tests passed. An additional
warranty-specific logout regression also passed separately.
Synthetic inventory baseline renders at 390/768/1440 pixels with text at 200%
were captured before UI edits; mobile and desktop were inspected. Warranty UI was subsequently implemented and captured below. These captures are
not native Windows acceptance.

## UI synthetic acceptance

The warranty dropdown is present only when the dates flag is enabled and the
store implements the separate warranty source. Initial load and All warranties
use the legacy list; selecting a dropdown value does not send a request until
Apply. Failed requests preserve the last loaded rows, applied predicate and UTC
reference with an explicit stale-data notice. No legacy fallback occurs on error.
The reference is retained on both Next and Previous (including return to page 1),
while Apply/Refresh at page 1 obtains a new server UTC day. Returning to All
warranties removes date-specific output. The filtered cards show warranty end.

Eight warranty widget cases passed, including capability gates, explicit Apply,
combined filters, stale failure, page date retention, refresh and disposed late
response, plus rendering at 390/768/1440 pixels with text scaling 200%. An earlier
combined run with eleven legacy inventory tests also passed. Mobile inspection
found a clipped long selected label; a short selected label (`Due within 30d`)
was applied while preserving the full menu label and precise reference text.
A new mobile capture confirms the selected label is readable. Legacy inventory
baseline captures match after-change captures byte-for-byte at all three widths
when the capability is unavailable. These checks are synthetic, not Windows
keyboard/screen-reader/native acceptance. Full Flutter integration passed analyzer and 392 tests, with one existing opt-in
test skipped. Regular deployment has not been performed; isolated results follow.

## Isolated PostgreSQL acceptance plan

A new fixed `warranty` profile reuses the existing bounded owned repository
lifecycle. `scripts/warranty-postgres-fixture.py` requires explicit synthetic
opt-in and an already present immutable PostgreSQL image. It provisions only a
new marked database/container/volume, binds one ephemeral port to 127.0.0.1,
applies 001/002/004 only there, runs once under the 120-second total command
budget and retains resources stopped after ownership-checked cleanup. It never
pulls an image, launches the backend or accesses the regular database.

The fixed suite has four cases: two-owner/null/exact-boundary behavior;
51 matching rows with search/status/category intersections before pagination;
Gregorian century/year-edge behavior; and unchanged rows, full exports and
overview after reads. Default Jest skips it without constructing a pool. Twenty
four offline orchestration tests across all existing repository profiles passed,
including four for the new profile. Typecheck passed. Live results follow;
no mocked result is treated as PostgreSQL acceptance.

## Live PostgreSQL result

One approved run completed at
`.local/asset-warranty-0a63a609e4af4aebf0c4b4e959b84aab/`.
The lifecycle report records completed status, four repository tests, synthetic
scope and stopped cleanup. The Jest report independently records all four named
cases passed, zero failures and zero pending cases. This establishes owner/date
predicates, literal filtering before pagination over 51 matches, calendar edges
and unchanged rows/exports/overview at repository scope. HTTP validation and real
Dart HTTPS transport were subsequently checked below. Windows native remains pending. No retry,
image pull, regular database update or deployment was performed.

## Live HTTPS result

One synthetic run completed at
`.local/asset-client-daa0a9609cae464787e6134e6df04649/` using the existing image,
localhost certificate and three loopback ports. No retry, dependency download,
trust change or regular backend/database update was performed. The lifecycle
report records `warrantyDartClient: true` and `cleanup: stopped`.

The real Dart driver checked anonymous denial, two-owner isolation, null and
inclusive date boundaries, 51 literal-search matches across two pages, combined
status/category filters, invalid/repeated query rejection, and sign-out refusal.
Read-only checks compared complete export records and overview counts before and
after filtering; v1 export still returned all 55 owned assets. SHA-256 used an
independent Python subprocess. Native dialogs were not exercised.

Six offline HTTPS orchestration tests, 24 proxy tests and Flutter analyzer passed.
The backend build and full default suite passed: 310 tests, 27 opt-in skips.
Codacy returned empty findings for the five changed HTTPS source/test files;
this is not proof of analyzer coverage or a security PASS. Windows native,
keyboard/screen-reader acceptance and regular deployment remain pending.

## Evidence provenance follow-up (offline only)

The historical HTTPS report above uses the common lifecycle hash list, which
omits the dedicated warranty driver and some warranty source/artifacts. It is
runtime evidence, not a complete source-provenance manifest. The report has not
been rewritten or retroactively assigned hashes.

The wrapper now returns an additional `warrantySourceHashes` map for its fixed
public source/artifact list. It hashes before and after the Dart task and refuses
success if a file changes or disappears. Env files, certificates and credentials
are not selected. This detects drift across the task, not arbitrary transient
changes or equivalence between TypeScript source and compiled JavaScript.

Nine offline wrapper tests passed, including exact hash coverage, unlisted
private-file exclusion, drift/deletion refusal and no driver invocation when
required source is missing. This wrapper follow-up has not been rerun against
live HTTPS; the historical runtime result remains scoped to the prior wrapper.

## Windows compilation (not native acceptance)

One release build completed from a short isolated selected-source copy with the
installed SDK/cache and `--no-pub`. Explicit defines use a loopback HTTPS fixture
endpoint and enable the existing dates capability. Import remains disabled.
No pub resolution, dependency installation, security-setting change or EXE launch
was performed. This is not a clean-checkout build or regular deployment.

The selected source still matched its recorded hashes after compilation; the
release EXE, Flutter DLL and ICU data were present. The complete release output
inventory and SHA-256 hashes are recorded in local evidence under
`.local/warranty-commit-review/windows-build-result.json`. The source selection is
recorded beside it. Windows interaction and screen-reader acceptance remain
pending; successful compilation does not prove SAC will permit launching the EXE.
