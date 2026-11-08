# Import v3 repository fixture plan

Status: one approved isolated PostgreSQL fixture passed all eight cases on
2026-10-28. No retry, pull, build or regular database access occurred.

## Boundary

Use fixed `import-v3` profile with an explicit opt-in token and an already-present
immutable PostgreSQL image ID. Never pull, install, build or select an existing DB.
Create one new labelled container and named volume, with one random port bound
only to 127.0.0.1. No host data bind mount or regular backend configuration.
Apply existing migrations 001/002/003/004/005 in that order only inside the fresh
synthetic database. Verify database identity and ownership marker before assertions.

The execution deadline is 120 seconds, with no automatic test retry. Readiness
polling is bounded separately inside that deadline. Cleanup has a 30-second budget,
checks ownership before stopping and retains container, volume and evidence.
Partial/skipped/malformed results or incomplete cleanup fail closed.

## Eight fixed scenarios

1. Insert 500 assets with alternating null location/dates and boundary dates;
   verify retained location/dates, version 1, ordered receipt and exact replay.
2. Changed location under the same owner/key conflicts without adding rows.
3. Reusing keys across v1/v2/v3 in both directions conflicts without mutation.
4. Same key under two synthetic owners produces separate owned assets.
5. Identical concurrent imports produce one asset set and one durable receipt.
6. Conflicting concurrent imports produce exactly one winner.
7. A fixture-only row failure rolls back every new asset and the receipt.
8. Lost acknowledgment after real COMMIT allows explicit same-key replay with
   durable IDs and no duplicates.

## Verification

Default Jest skips all eight cases without creating a pool. Offline lifecycle
checks use mocked commands and temporary synthetic files, not Docker or a database:

```powershell
python -B scripts/test_import_v3_postgres_fixture.py -v
pnpm --dir backend typecheck
pnpm --dir backend test -- --runTestsByPath src/domains/assets/asset-import-v3.postgres.spec.ts --runInBand --silent
```

Entry point: `scripts/import-v3-postgres-fixture.py`. Real execution requires
separate approval and a locally inspected immutable image ID. This fixture does
not prove HTTPS/auth, client integration, recovery, UI or Windows acceptance.
No migration, deployment, commit or push is authorized by source preparation.

## Observed repository acceptance

Fixture `asset-import-v3-96b6ae7a90e3a4b57027fb303a98175f` completed:
8 passed / 8 total, zero failed or skipped. The runner exited successfully and
independent Docker inspection confirmed a stopped container, matching ownership
labels on container and volume, loopback-only port configuration and one retained
named volume without host data bind mounts.

Local ignored evidence: `.local/asset-import-v3-96b6ae7a90e3a4b57027fb303a98175f/`
(`result.json`, `jest-result.json`). Image used:

```text
sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24
```

This proves the eight repository scenarios only. HTTPS/auth, Dart integration,
native recovery/UI and deployment remain unverified for import v3.
