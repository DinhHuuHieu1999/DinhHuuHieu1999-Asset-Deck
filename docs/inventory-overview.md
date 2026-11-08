# Inventory overview

Status: backend/client/UI source in progress; not deployed or natively accepted.

## Contract

`GET /api/v1/assets/overview` is authenticated and read-only, with `no-store`.
It summarizes the complete inventory of the authenticated owner, independently
of list search, status/category filters, pagination and the export limit.
No owner identifier is accepted from the caller. No asset names, serials or notes
are returned. Counts are observations, not an export or database backup.

The response contains `complete: true`, `total`, `byStatus` (all four statuses,
including zero counts) and `byCategory` (exact case-sensitive category labels and
counts). Empty inventory returns zero totals and an empty category array.
Categories are sorted by ordinal label order in application code. Labels remain
inert text, including percent, underscore and Unicode.

One PostgreSQL statement groups owner rows by category/status, providing a single
statement snapshot. At most 200 distinct categories are supported. The query reads
at most 801 groups: four statuses per category mean any truncated result must
already exceed the category limit. More than 200 categories returns HTTP 422,
never partial counts. Malformed or unsafe integer counts fail closed.
No schema change, production dependency or mutation is introduced.

## Client acceptance plan

Add an explicit read-only overview screen reached from inventory, not a count
computed from the current 50-row page. Explain that overview ignores list filters.
Refresh explicitly; retain previous successful counts on error with a stale-data
notice. Show loading, empty, auth and limit failures without interpreting them as
zero inventory. Sign-out must clear private navigation and late responses.
Capture and inspect synthetic rendering before UI edits and verify at 200% text.

Repository acceptance is recorded below; HTTPS ownership and transport checks
were pending at the source review point; later acceptance is recorded below.
Backend unit tests alone do not prove real SQL or HTTP behavior.
Windows native acceptance remains pending. Do not retry
blocked executables or change Windows protection to obtain acceptance.

## Source verification to date

Backend typecheck and 197 unit tests passed; 11 opt-in tests were skipped.
The Dart client adds a separate overview capability without changing list-only
store implementations. Its immutable parser requires both breakdowns to sum to
the total and rejects missing statuses, duplicate categories, unsafe counts and
incomplete responses. It uses the existing bounded transport/session checks.
Client/model transport tests and analyzer are exercised separately; these do not
prove real PostgreSQL/HTTPS behavior. The read-only UI and explicit inventory navigation are now implemented;
synthetic visual and behavior checks are separate from native acceptance.

## Isolated repository acceptance

The fixed overview profile reuses `scripts/category-postgres-fixture.py` lifecycle
through `scripts/overview-postgres-fixture.py`. Eight existing lifecycle tests and
four overview profile tests pass offline. Default Jest invocation skips all four
repository scenarios without creating a database pool.

One approved isolated PostgreSQL run passed all four scenarios without skips or
retry: full counts beyond one list page, exact literal/case-sensitive categories,
two-owner and empty-account isolation, the 200/201-category boundary, and coherent
counts while an uncommitted update transaction is open and after commit. This last
check verifies committed visibility; it does not claim every race interleaving.
The runner used an existing immutable image, new synthetic resources and one
random loopback port. It reported stopped cleanup, independently verified with
the exact ownership label. Container/volume and local result files are retained.
No normal backend/database, TLS trust, Windows protection or deployment changed.

Flutter full unit/widget verification passed 247 tests with one opt-in skip;
analyzer reported no issues. Synthetic renders at 390/768/1440 pixels and 200%
text were generated; the narrow layout was inspected before and after UI changes.
The local capture font lacks CJK glyphs, so native Unicode display is unproven.
At that checkpoint HTTPS acceptance was pending; the subsequent result follows.
Native UI and security analyzer coverage remain pending.

## Isolated HTTPS acceptance

The first run failed with insufficient diagnostic detail. A separately approved
new diagnostic fixture located failure at `empty-overview`. Source inspection
showed the test-only TLS proxy denied the new route before reaching the backend.
The proxy now allows only the exact GET overview path, with regression coverage
for rejected write methods and neighboring paths; all 21 proxy tests pass.

A subsequent separately approved new fixture passed the real Dart client checks:
empty counts, 53 records spanning pages, exact case/Unicode category labels,
two-owner isolation, unchanged record fields after overview reads, and updated
counts after an explicit asset edit. Marker binding and default TLS validation
remained enabled. Shared lifecycle reported stopped cleanup; native acceptance
remains pending. The client overview-limit error label was subsequently clarified
and checked offline; that message-only change was not part of the live run.

Five HTTPS orchestration tests validate fixed source/endpoint selection and
fail-closed output. Sanitized stage diagnostics retain only whitelisted stage
names, never exception bodies or credentials. Guard tests refuse missing opt-in
and regular endpoints before registration. The fixture results are not security
coverage, Windows native acceptance or a regular deployment.

## Unicode review correction

A source regression reproduced rejection of 64 astral Unicode code points because
UTF-16 length was used instead of the database character limit. Overview aggregate
and client parsing now count Unicode code points; the 65-code-point case remains
rejected. This correction is scoped to overview labels and does not change asset
input validation or silently normalize category identity. It was made after the
live fixtures above, so those runs do not prove the astral boundary correction.
