# Complete inventory warranty overview

Status: backend, Dart client, synthetic widgets and isolated PostgreSQL repository
and real Dart HTTPS acceptance verified. Windows native acceptance remains pending.
No regular deployment.

## Product semantics

Count the entire authenticated owner's inventory, independently of current list
search, status, category, warranty mode or page. All four asset statuses count.
For one explicit UTC calendar reference (`asOf`) and its inclusive 30-day horizon
(`through`), the groups are disjoint and exhaustive:

| Field          | Meaning                                            |
| -------------- | -------------------------------------------------- |
| `expired`      | Known end strictly before `asOf`                   |
| `expiringSoon` | Known end from `asOf` through `through`, inclusive |
| `later`        | Known end strictly after `through`                 |
| `unknown`      | Null warranty end                                  |

Their sum must equal `total`. Expiry today is upcoming, not expired. Empty
inventory returns complete zero counts. Unknown does not mean expired or safe.
The existing Gregorian calendar rules and year-9999 horizon saturation apply.

## API and persistence boundary

Authenticated `GET /api/v1/assets/warranty/overview` accepts only optional `asOf`
(strict Gregorian YYYY-MM-DD); omission uses the server UTC day. Repeated,
malformed and unknown query fields are rejected through the existing validation
pipe and calendar helper. Owner comes only from authentication. Caller-selected
`asOf` changes the comparison date, not the inventory's historical snapshot.

The exact response fields are `complete: true`, `asOf`, `through`, `total`,
`expired`, `expiringSoon`, `later`, `unknown`. Counts are non-negative safe JSON
integers. Malformed/inconsistent database aggregates fail; overflow returns 422,
never a partial response. No serials, notes, asset IDs or owner ID are returned.
Responses use `Cache-Control: no-store` and existing auth/session middleware.

The existing dates module/flag and migration 004 readiness gate own this route.
No new flag, migration, dependency, worker, notification or remote lookup is added.
One parameterized aggregate statement counts the owner at a statement snapshot.
No grouping/category cap, list filter, row projection or pagination is applied.
The existing category/status overview and legacy list/export contracts are unchanged.

## Client and UI acceptance requirements

Use a separate optional read capability so existing list-only stores remain valid.
Validate exact response shape, complete flag, strict reference/horizon, safe counts
and sum before rendering. Reuse the bounded authenticated transport and session
invalidation. Unsupported dates must not silently fall back to partial list counts.

Capture and inspect the existing rendered overview before UI changes. Label the
UTC reference and complete-inventory scope. Require explicit refresh, retain last
successful counts with a stale warning on failure, and distinguish a valid empty
inventory from a failed request. Verify narrow/wide screens at 200% text and
sign-out/late-response behavior. Synthetic widgets do not establish native acceptance.

## Verification to date

The new backend suite first failed because its implementation did not exist.
After implementation, backend typecheck and 77 focused tests across overview,
warranty calendar and list boundaries passed. Checks cover canonical PostgreSQL
bigint strings, zero/max-safe counts, inconsistent sums and overflow; query/auth
boundaries; UTC reference default and year saturation; one owner-bound SQL
statement with four predicates; missing/duplicate aggregate rows and DB failures.

These are unit/mock checks, not real SQL bucket partition/concurrency/ownership
acceptance. No fixture or backend process was started for this phase. Future
runtime acceptance requires a separately approved isolated fixture. Do not infer
native or security PASS from tests, compilation or empty Codacy findings.

The full default backend suite subsequently passed 337 tests with 27 existing
opt-in skips. No real database connection was used for these default checks.

## Dart client and baseline render

A separate `AssetWarrantyOverviewSource` capability preserves legacy stores.
The immutable parser requires the exact eight fields, a complete flag, strict
calendar/reference echo, the computed horizon, non-negative safe counts and an
exact total. The client sends only optional `asOf` on the authenticated read route;
invalid references are refused before HTTP. It uses the existing bounded
transport and session epoch checks, without retry or fallback to list data.
Count-overflow 422 has its own message, not pagination guidance.

Flutter analyzer and 125 combined model/transport tests passed, including legacy
transport regressions, missing/extra fields, malformed/overflow counts, Gregorian
edges, authentication, query encoding, HTTP failures and late sign-out response.
These use a synthetic HTTP server, not the product backend or HTTPS fixture.

Before UI changes, the existing overview rendered at 390/768/1440 pixels with
200% text. The narrow and desktop images were inspected under
`.local/warranty-overview-ui/before/`. The layout is a centered, scrolling,
text-first overview with explicit refresh and scope. The capture font lacks CJK
glyphs for historical category labels; these renders do not certify native Unicode
or screen-reader behavior.

## Warranty overview screen

A separate read-only screen is available only when dates are enabled and the store
supports the warranty overview capability. Opening it does not apply or discard
inventory search drafts. It shows all four counts, the UTC reference and inclusive
horizon, with explicit refresh. Failed refresh keeps the previous counts with a
stale-data warning; initial failure never displays a fabricated zero inventory.
Source replacement or disposal prevents late requests from updating the screen.

Fourteen widget tests passed, covering capability gating, navigation/draft preservation,
all buckets, pending disposal, stale failures, initial failure, source replacement
root sign-out with loaded and pending results, valid empty inventory, sanitized
unexpected failures,
and 390/768/1440-pixel renders at 200% text. Narrow and desktop after-images were
visually inspected in `.local/warranty-overview-ui/after/`; the narrow page scrolls.
The final full Flutter suite passed 466 tests with one opt-in skip; analyzer found no
issues. These are synthetic renders, not Windows native or screen-reader acceptance.
Individual Codacy calls returned success with empty findings; this does not certify
analyzer coverage or security. No source commit or live fixture was performed.

## Isolated PostgreSQL acceptance scope

Before runtime acceptance, use a new synthetic database/container with the existing
image, migrations and a loopback-only port. Never reuse the regular database.
No pull, dependency installation, real data mounts or retry is required.

Verify the actual repository aggregate against these cases:

1. Empty owner returns four zero buckets and a zero total.
2. More than one list page, across all statuses/categories, is counted completely.
3. Dates before reference, exactly reference, exactly day 30, day 31 and null
   partition into the expected buckets; their sum equals total.
4. A second owner's records do not affect counts or disclose identifiers.
5. Leap-day and year-9999 horizons retain strict calendar semantics.
6. More than 200 categories do not inherit the legacy category overview limit.
7. A controlled concurrent date edit yields one statement-consistent partition,
   not counts assembled from separate requests.

Record explicit date references, expected/actual counts and unchanged row hashes.
Use a total deadline, verify resource ownership before stopping, and retain the
stopped synthetic container/volume and evidence. A separate approval is required
before executing this fixture. SQL acceptance does not replace later real Dart
HTTPS/auth and Windows native acceptance.

## Prepared opt-in repository harness

`scripts/warranty-overview-postgres-fixture.py` dispatches the fixed
`warranty-overview` profile through the existing bounded repository lifecycle.
The profile requires its own database prefix, environment opt-in and ownership
marker, plus migrations 001/002/004. It uses only an existing immutable image,
a new synthetic volume and one random loopback port, with a 120-second runtime
deadline. Ownership is checked before stopping; resources are retained, not removed.
No dependency installation, image pull, backend startup or retry is included.

After separate operator approval, the intended invocation is:

```powershell
python -B scripts/warranty-overview-postgres-fixture.py --execute-synthetic --image sha256:<verified-existing-image-id>
```

The fixed Jest suite has seven scenarios. It checks empty inventory, 57 records
across all four statuses, exact day/null boundaries, two owners, leap/year-limit
dates, 201 categories, and visibility before/after another transaction commits.
The concurrency check holds an uncommitted date edit during the read; it does not
claim exhaustive stress testing of every concurrent schedule.

Source acceptance: backend typecheck passed; all 29 offline repository-lifecycle
tests passed, including five new overview checks. The seven SQL scenarios are
skipped without explicit opt-in, as verified locally. At that source-only checkpoint, PostgreSQL execution
had not occurred; see the live acceptance below. Codacy returned empty findings on the four harness/source files;
this is not proof of runtime correctness or security coverage.

## Isolated repository acceptance: 2026-10-27

One approved fixture run completed with all seven scenarios passed, none skipped
or failed, using the existing PostgreSQL image and the prepared repository source.
No retry, image pull, dependency installation or regular backend access occurred.
The owned container was stopped; an independent read-only Docker check confirmed
`Running=false`, the expected ownership label, and the retained synthetic volume.

Local evidence: `.local/asset-warranty-overview-6c78e60a50c8c84d4610eb41b9544ca5/`
contains `result.json` and `jest-result.json`. The result records seven completed
repository tests and stopped cleanup. This proves the exercised aggregate SQL,
owner partition and controlled transaction visibility, not HTTPS routing/auth,
Dart-to-backend integration, Windows native behavior or stress-test coverage.
No source was committed, pushed or deployed to the regular backend.

## Prepared HTTPS source harness (not executed)

`scripts/warranty-overview-https-fixture.py` selects a fixed Dart acceptance driver
and reuses the existing owned HTTPS lifecycle with dates enabled and import off.
It requires the overview model/controller/repository source and built artifacts,
hashes the selected public files before/after the run, and refuses drift or missing
files. No env, certificate or key is included in the hash list. The driver uses
normal TLS verification and checks the exact synthetic proxy marker before login
or writes. It never accepts an arbitrary API target or bypasses certificate checks.

The real `AssetApi` driver is prepared to verify anonymous refusal, empty counts,
55 owner assets across four statuses/two categories, explicit/default UTC reference,
all four buckets, two-owner isolation, invalid/extra/repeated query rejection,
unchanged complete v2 export records after reads, and refusal after sign-out.
Python SHA-256 is used only through the existing bounded stdin digest helper.
Failure evidence retains only an allowlisted stage, not tokens or exception text.

Offline acceptance: 18 HTTPS orchestration tests passed (nine new and nine legacy),
including missing-each-file preflight, exact typed result, one fixed invocation,
source drift, incomplete result, private-file exclusion and sanitized diagnostics.
Flutter analyzer reported no issues for the prepared driver. Codacy returned empty
findings on the three new files; this does not establish analyzer coverage.
No build, HTTPS fixture, certificate/key read or runtime acceptance occurred here.
A separately approved backend build and one isolated HTTPS run remain required;
Windows native acceptance and regular deployment remain pending.

## First HTTPS attempt: incomplete, no retry

The approved backend candidate build succeeded. One isolated HTTPS fixture reached
Dart stage `anonymous`, then failed before account registration or asset creation.
Evidence is retained in `.local/asset-client-a315b21d9f62b4748204d469506593d3/`.
The result records failed acceptance and stopped cleanup; HTTPS remains pending.

A source-level regression reproduced the cause: the test-only TLS proxy allowlist
did not include `/api/v1/assets/warranty/overview`, so it denied the request before
backend authentication. The proxy now allows only the exact GET route with explicit
dates capability, including query forwarding for backend validation. Other methods,
default/import-only profiles and additional path segments remain denied. The new
regression failed before the patch; all 25 proxy tests and 18 HTTPS orchestration
tests passed afterward. Codacy returned empty findings on the two changed files.
No second fixture was run. A separately approved new fixture is required; these
source tests do not prove the corrected live HTTPS workflow.

## Corrected isolated HTTPS acceptance: 2026-10-27

A separately approved new fixture completed once using the existing backend
candidate and corrected test proxy. The real Dart client passed anonymous refusal,
empty inventory, 55 owner assets with four statuses/two categories, explicit and
default UTC references, all four counts, second-owner isolation, invalid/extra/
repeated query rejection, identical complete v2 export records after reads, and
refusal after sign-out. Standard TLS checks and the synthetic marker were retained.
No retry, dependency installation, trust/firewall change or regular deployment
occurred. The failed first run remains recorded above rather than reclassified.

Evidence: `.local/asset-client-6c1d84d331d4750b8a235cce4d20e461/result.json`
records completed stage, `warrantyOverviewDartClient=true`, stopped cleanup and
21 selected public source/artifact hashes. An independent Docker read confirmed
`Running=false`, the expected ownership label and retained synthetic volume.
Windows native acceptance remains pending; HTTPS success does not substitute for
native rendering, keyboard/screen-reader checks or regular-backend rollout.
