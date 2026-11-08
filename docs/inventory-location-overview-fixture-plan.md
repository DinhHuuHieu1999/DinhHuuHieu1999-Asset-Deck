# Location overview PostgreSQL fixture plan

Status: harness source and offline tests only; live execution not approved.

Use `scripts/location-overview-postgres-fixture.py` with an explicit synthetic
opt-in and an existing PostgreSQL image ID. The shared repository lifecycle
creates a new labeled container/volume, synthetic account/database and identity
marker. Bind one random database port to 127.0.0.1 only. No image pull, real data
mount, backend build or HTTPS is needed. Apply existing migrations 001/002/004/005.

Run exactly four opt-in repository cases with a total lifecycle deadline of
120 seconds, no retry:

1. Empty owner: complete zero counts.
2. Sixty assets: counts beyond one list page, case-sensitive literal percent/
   underscore labels, null bucket and a separate owner's group excluded.
3. Explicit location clear: group moves to unknown; base fields stay unchanged.
4. Exactly 1,000 known labels succeeds; one more refuses partial output.

Verify identity before SQL/test execution and ownership before stopping. Keep
container, volume and evidence after the fixture; never automatically delete.
Missing source/image, wrong ownership, skipped cases or partial test results fail
closed. Five mocked lifecycle tests pass without Docker. The four live cases
skip by default. These checks do not establish HTTPS/auth, concurrent snapshot
behavior, native acceptance or deployment readiness.

## Observed repository acceptance

One separately approved execution completed all four cases without skips or retry.
Fixture `ae3ab6ac58bed82157faf5240755e90d` reported completed/stopped; independent
Docker inspection confirmed a stopped container and retained volume with the
matching ownership label and loopback-only binding. Source tests and repository
acceptance do not establish HTTPS or native interaction acceptance.
