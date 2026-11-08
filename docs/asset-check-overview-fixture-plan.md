# Check-date overview PostgreSQL fixture

Status: approved isolated PostgreSQL execution passed all four scenarios.

## Isolated execution boundary

Use `scripts/check-overview-postgres-fixture.py` only with explicit
`--execute-synthetic` and an existing immutable `--image sha256:...`.
The shared repository lifecycle creates a new synthetic database, owned
container and volume, and a random port bound only to loopback. It applies
migrations 001 through 006 and an identity marker before running the fixed
`asset-check-overview.postgres.spec.ts` suite once. It never pulls an image,
retries assertions, mounts regular data or starts the application backend.
The total execution deadline is 120 seconds. Cleanup checks resource ownership,
stops the container and retains its volume and local evidence.

## Four required scenarios

1. Empty owner returns a complete zero partition.
2. More than one page partitions Unknown / before / on-or-after correctly,
   including exact cutoff equality and a separate owner's data. Before
   pagination and inclusive drill-down match the overview counts.
3. Inclusive cutoff remains exact with literal search, status, category,
   location and warranty combinations; another owner cannot see those rows.
4. Overview reads at minimum/maximum calendar cutoffs and invalid cutoff
   handling do not change stored rows.

All four tests must pass with no skipped, failed or runtime-error tests.
The default backend test command skips this opt-in suite before pool creation.
Five mocked lifecycle tests verify exact dispatch, identity, migrations,
missing-source refusal, strict result counts and owned cleanup. These tests do
not establish SQL runtime acceptance. HTTP/auth and Windows remain separate
acceptance layers. No commit, deployment or Codacy/security approval is implied.

## Recorded PostgreSQL acceptance

The single approved run completed with four passed tests, no skips, no failures
and no runtime errors. Evidence is retained locally under
`.local/asset-check-overview-072c7898701bbea4346ab2a504d6a90a/`.
The owned container was stopped and its volume retained. No regular database,
application backend or Windows client was changed. This proves repository SQL
behavior only; real HTTPS client and native UI acceptance remain pending.

## HTTPS source harness (not executed)

`scripts/check-overview-https-fixture.py` reuses the existing exclusive check-date
TLS lifecycle and real Dart driver. It requires the new compiled overview
artifact and source before resource creation, hashes the fixed inputs, and
accepts only the exact typed completion result with overview acceptance true.
The shared driver retains its default output when the overview probe is absent.
The overview probe verifies anonymous refusal, empty owner isolation, Unknown /
before / equality / after counts, all four list route combinations, and stable
asset versions after read-only overview/list requests. It creates synthetic
records only. Nine mocked harness tests pass; real HTTPS execution is pending.

The next separately approved action is one backend candidate build and one
isolated HTTPS fixture using existing PostgreSQL image, localhost certificate
and SDK. No dependency installation, trust/firewall changes, retry, regular
backend/database changes, native launch, commit or deployment are included.

## First HTTPS run and offline repair

The single approved HTTPS run failed in the anonymous stage because the
fixture proxy did not allow the new overview route. Owned resources stopped
successfully; no retry was performed. Evidence remains in
`.local/asset-client-e3a90e02348b438454daa55128ca2bc5/`.

Adding the regular `AssetsController` before `AssetCheckController` in the
synthetic HTTP test separately reproduced a second integration defect: the
single-segment overview URL was captured by `assets/:id` and returned 400.
The endpoint is now `GET /assets/check-overview/counts?cutoff=YYYY-MM-DD`,
which does not overlap that route. The test keeps both controllers to protect
registration order. The fixture proxy permits only explicit check capability,
GET, and one bounded cutoff query. Four HTTP tests, backend typecheck and 38
proxy tests passed after repair. A fresh build and separately approved HTTPS
run are required; the failed runtime attempt is not acceptance.

## Approved repaired HTTPS run

A separately approved rebuild and single new HTTPS run completed successfully.
The real Dart client verified anonymous refusal, owner-separated complete
partitions, strict equality boundaries, all four inclusive list combinations
and unchanged versions after reads. The existing check-date / checked-before
acceptance also passed. Source hashes were unchanged during execution.
Evidence is retained at
`.local/asset-client-f4174fe754a11c3787e8b384db24d869/`.
The exact owned container was independently confirmed stopped; volume and
local evidence remain. No retry, regular backend change, native launch,
commit or deployment was performed. Windows acceptance remains pending.
