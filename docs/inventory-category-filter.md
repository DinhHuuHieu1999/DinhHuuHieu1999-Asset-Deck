# Inventory category filter

Status: committed source; backend and client/UI implemented; repository and HTTPS fixtures passed; native acceptance pending. Not deployed.

## Contract

`GET /api/v1/assets` accepts optional `category` alongside `q`, `status` and
`offset`. Omitted or trimmed-empty category selects all categories. Otherwise,
the trimmed value matches category exactly, including case. The raw query value
must be a string of at most 64 characters without NUL. Arrays/null are invalid.
Percent, underscore, quotes and Unicode are data, not wildcard or SQL syntax.

All filters are combined with AND under the authenticated owner before the
existing fixed-size pagination. No category discovery endpoint, dependency or
migration is introduced. Export continues to include the full owner inventory,
independently of list filters. Existing callers may omit the new parameter.

## Source verification and remaining acceptance

- Dart list boundary and transport accept an optional category argument.
- Before/after synthetic inventory renders were inspected at 200% text.
- Category input retains applied filters across paging/refresh; applying
  new filters starts page one. A failed load retains the last successful results.
- Client/UI tests cover combined filters, invalid input without a request,
  failed Apply preserving the loaded category, paging with an unapplied draft,
  and category preservation when returning from Export/Inspect.
- Separately authorized PostgreSQL/HTTPS checks must prove exact matching,
  filtering before pagination and two-owner isolation; mock SQL checks alone do not.
- Native acceptance, deployment and commit remain separate decisions.

Full backend suite: 184 passed, seven opt-in tests skipped; typecheck passed.
Full Flutter suite: 225 passed, one opt-in test skipped; analyzer passed.
These results do not prove live database or native behavior.

## Proposed isolated acceptance

Use a new synthetic PostgreSQL database/container with the existing image, no pull
or real data mount, a port bound only to loopback and a verified ownership marker.
Keep all regular services and data unchanged. No runtime schema change is needed.

Required repository assertions:

1. More than 50 matching owner records paginate correctly even when newer records
   in a different category would otherwise occupy the first page.
2. Category plus literal search and status uses AND, with no other-owner rows.
3. Case variants remain distinct; leading/trailing query whitespace is trimmed.
4. Percent, underscore, quotes and Unicode match literal category values.
5. Empty category restores unfiltered behavior; unmatched category returns empty.
6. Full export remains complete and independent of prior list filters.

A separate HTTPS check must exercise DTO validation and the real Dart client;
repository assertions alone cannot prove that boundary. Run only after approval,
with a total deadline, no retry, ownership-checked shutdown and retained output.
Do not infer Windows native acceptance from headless checks or retry the blocked
recovery EXE as part of this category phase.

## Repository fixture source

`backend/src/domains/assets/assets-category.postgres.spec.ts` defines four grouped
scenarios for the assertions above. It is skipped by default and constructs its
pool only inside the opted-in suite. Before seeding it verifies a loopback URL,
nonstandard explicit port, dedicated database name and exact fixture marker.
It never migrates or deletes data. Typecheck passed; default invocation skipped
all four tests. The initial default run did not execute PostgreSQL; later isolated evidence is recorded below.

Execution requires a separately approved harness to provision the synthetic
database and marker and enforce ownership, deadline and shutdown. Setting the
opt-in environment variable alone is not a substitute for that authorization.

The opt-in runner is `scripts/category-postgres-fixture.py`; its eight offline
contract tests cover prerequisites, exact Jest result validation, one invocation,
ownership refusal, assertion failure cleanup and verification that the owned
container actually stopped. The later approved repository run is recorded below. It uses a 120-second
scenario deadline plus a separate bounded cleanup budget, keeps the stopped
container/volume, and neither pulls images nor launches a backend.

## Isolated repository acceptance

One approved run completed all four grouped assertions with no skipped tests or
retry. It used an existing immutable PostgreSQL image, a new synthetic database,
container and retained volume, and a random port bound only to loopback.
The runner reported cleanup stopped; independent Docker inspection confirmed
`State.Running=false` and the exact fixture ownership label.

This verifies category predicates, literal/case matching, pagination, owner
isolation and snapshot independence at the repository boundary. It does not
prove the HTTP DTO path, real Dart HTTPS transport, native UI or deployment.
No regular backend/database was changed. Source was uncommitted at that
repository acceptance point; the later commit is recorded below.

## HTTPS acceptance source

`scripts/category-https-fixture.py` reuses the existing owned HTTPS lifecycle.
It first verifies the random marker with default TLS trust and no redirects,
then probes actual DTO handling of overlong/NUL/repeated/nested category inputs
and valid empty/literal/max-length queries using a synthetic account.
A dedicated Dart process then verifies real-client category encoding and combined
filtering, two-owner isolation, case/literal matching and multiple pages.

Five Python orchestration tests and five Dart/shared guard tests passed offline;
the driver analyzer passed. These do not prove HTTPS execution. At that source-review point, a freshly built backend and separately approved
fixture run were still required; the later result follows.
No native application launch is needed for this headless acceptance step.

## Isolated HTTPS acceptance

One approved fresh backend build and HTTPS fixture completed without retry.
Actual HTTP validation rejected overlong, NUL, repeated and nested category
inputs and accepted empty, literal and maximum-length queries. The real Dart
client verified 51 matching records across pages, exact/case-sensitive and Unicode
category values, combined search/status and two-owner isolation.

Default TLS validation remained enabled. Shared lifecycle reported cleanup
stopped; independent Docker inspection confirmed the matching label and stopped
state, and all three selected loopback ports had no listeners. The old backend
build, fixture files and volume were retained. No regular service was restarted,
no native app was launched, and no push or deployment followed. Source was
subsequently committed as recorded below.

Native UI acceptance and complete security analyzer coverage remain unproven.
Do not apply the earlier recovery EXE block as proof this category candidate
works or fails natively; no category Windows build/launch has been attempted.

## Committed source verification

Commit `7311879` contains the 19 category implementation, test and contract files.
A separate Git archive of that commit passed all 13 Python orchestration tests
(eight PostgreSQL-runner tests and five HTTPS-runner tests), without copying local
dependencies, runtime or env files. This verifies committed offline harness
contracts, not live execution from a fresh checkout or Windows native behavior.
