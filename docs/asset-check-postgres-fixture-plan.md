# Manual check-date repository fixture plan

Status: one approved isolated execution completed; 4/4 repository scenarios passed.

The opt-in suite is `backend/src/domains/assets/asset-check.postgres.spec.ts`.
Default tests skip all four scenarios without constructing a database pool.
Typecheck passes; skipped tests are not database acceptance.

## Proposed isolated lifecycle

Reuse the bounded category/location lifecycle rather than introduce another Docker
implementation. The fixed check profile uses an existing image (no pull), new synthetic
container/volume/database, one random loopback port, and a total 120-second deadline.
Apply migrations 001 through 006 in order. Create the exact fixture marker table
only in that new database. Refuse normal database names and ports 5432/5433.
Verify container/volume identity before stopping; retain evidence and data. Never
retry automatically or read regular backend credentials.

The suite requires all three explicit environment values:

- `ASSET_CHECK_FIXTURE_OPT_IN=isolated-check-v1`
- `ASSET_CHECK_FIXTURE_URL`: a loopback URL naming `asset_check_fixture_<12 hex>`
- `ASSET_CHECK_FIXTURE_MARKER`: 32 hex characters matching the database marker

Do not point these values at an existing operator database. The wrapper is `scripts/check-postgres-fixture.py`; its execution flag is
`--execute-synthetic` and it requires `--image sha256:<64 lowercase hex>`.
Do not execute it until the operator approves one isolated run.

Offline checks: `python -B scripts/test_check_postgres_fixture.py -v` (5 tests),
plus the category and location lifecycle suites (13 tests). They verify exact
profile/marker/env, migration order, missing-file preflight, one Jest run,
fail-closed results and ownership-aware cleanup using mocked commands only.

## Four database scenarios

1. Owner isolation, shared-version conflict, exact date storage, and preservation
   of purchase/warranty dates, location and base fields.
2. Two concurrent same-version writes: exactly one winner.
3. Explicit clear returns Unknown and preserves base fields.
4. Unknown filtering before pagination: 51 matching owner rows across two pages,
   excluding a checked row and another owner's row; literal `%_1` serial search.

This suite does not establish HTTPS, real authentication, restore or native UI
acceptance. Those remain separate gates. No commit/deploy is implied.

## Verified execution

The single approved run completed all four assertions without skips or retries.
Its owned container was stopped and the synthetic volume/evidence retained.
Evidence is local-only under `.local/asset-check-007601d4fd05ff10087ac8dc2f38cdc3/`.
This does not authorize another run, rollout, HTTPS or Windows acceptance.
