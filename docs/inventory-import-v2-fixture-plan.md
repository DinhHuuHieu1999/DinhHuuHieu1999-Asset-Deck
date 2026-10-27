# Import v2 repository fixture plan

Status: one explicitly approved isolated PostgreSQL execution passed all eight
assertions on 2026-10-27. No retry, pull, build or regular database access occurred.

## Isolated execution boundary

Reuse the bounded repository lifecycle with fixed `import-v2` profile and a
separate exact opt-in token. Require an already-present immutable PostgreSQL image;
never pull/install/build. Create one new labelled container and named volume,
with only one random port bound to 127.0.0.1 and no host data bind mounts.
Use fresh database, marker and synthetic owners. Refuse identity mismatches before
seeding or executing assertions. Apply existing migrations 001/002/003/004 only
inside this new database; never migrate the regular backend on startup.

Total execution budget is 120 seconds; no automatic test rerun. Bounded readiness
polling is not an acceptance retry. Cleanup has its existing separate 30-second
budget, verifies ownership before stopping, and retains container/volume/evidence.
Incomplete cleanup, skipped tests, or fewer/more than eight assertions fail closed.
No HTTPS, app, provider, model, real account or Windows security changes.

## Eight fixed scenarios

1. Insert 500 records with alternating explicit nulls and calendar boundary dates;
   verify dates, version 1, receipt ordering and exact replay without extra rows.
2. Changed contents conflict for the same owner/key without adding rows.
3. Reuse a key across v1/v2 in both directions: conflict, no mutation.
4. Same key under different synthetic owners remains isolated.
5. Concurrent identical batches yield one durable receipt and asset set.
6. Concurrent conflicting batches yield exactly one winner.
7. Inject a fixture-only row failure: all rows and receipt roll back.
8. Lose acknowledgment after real COMMIT: explicit replay returns durable IDs,
   without duplicate rows or a new key.

## Entry points and evidence

Source runner: `scripts/import-v2-postgres-fixture.py`, using the existing shared
repository lifecycle. Suite: `backend/src/domains/assets/asset-import-v2.postgres.spec.ts`.
The default Jest run skips the eight database cases without constructing a pool.
Offline test command (does not run Docker or PostgreSQL):

```powershell
python -B scripts/test_import_v2_postgres_fixture.py -v
```

Actual execution requires separate operator approval and an inspected immutable
image ID. Do not use a mutable tag or adapt the runner to an existing database.

## Observed repository acceptance

Fixture `asset-import-v2-e2d3ed81c11609de634286ad111a7279` completed with
8 passed / 8 total, zero failed or pending assertions. Image ID:

```text
sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24
```

Local ignored evidence lives under `.local/asset-import-v2-e2d3ed81c11609de634286ad111a7279/`
(`result.json` and `jest-result.json`). Reviewed source hashes matched before
execution. Independent Docker inspection confirmed matching container/volume
ownership labels, stopped container, a loopback-only port binding and a retained
named volume (no host data bind mount). Native acceptance remains pending.
This demonstrates repository behavior only, not HTTPS/auth/client integration,
backup/restore, a Windows UI or regular deployment. No source was committed/pushed.
