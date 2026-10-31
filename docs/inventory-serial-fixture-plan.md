# Serial warning repository fixture

Status: source/offline contracts and one separately approved PostgreSQL run passed.
Any further live execution requires separate approval.

## Boundary

The fixed `serial-postgres-fixture.py` wrapper reuses the owned repository lifecycle.
An explicit `--execute-synthetic` flag and an existing immutable PostgreSQL image
ID are mandatory. No image pull, dependency installation, backend build, HTTP,
provider call or regular database access is allowed.

The proposed execution creates a new labeled synthetic container and named volume,
with one random port bound only to `127.0.0.1`. It applies migrations 001 and 002
only, creates a marker table, and checks database and resource ownership before
seed/assertions and cleanup. Jest runs once under a total 120-second work deadline;
cleanup has a separate bounded allowance. There is no test retry. Owned resources
are stopped and retained, not deleted. Changed ownership refuses cleanup.

## Four scenarios

1. Literal, case-sensitive equality: `%`, `_`, SQL punctuation, blank and Unicode.
2. Two owners; exclude the current asset only inside the authenticated owner's rows.
   A foreign asset ID must not reveal or suppress another owner's results.
3. A serial older than more than 50 newer rows is still found. Compare both owners'
   snapshots before/after reads to prove no record mutation.
4. Creating and optimistically updating duplicate serials remains permitted.

Default Jest execution skips all four scenarios without constructing a pool.
Mock tests verify fixed routing, missing source and opt-in refusal, exact result
counts, one Jest invocation and cleanup success/ownership/failure boundaries.
Mock success is not PostgreSQL acceptance. Auth/CSRF, HTTPS and native acceptance
are not covered by this repository-only fixture.

## Offline verification

```powershell
python -B -m unittest discover -s scripts -p test_serial_postgres_fixture.py -v
python -B -m unittest discover -s scripts -p test_category_postgres_fixture.py -v
python -B -m unittest discover -s scripts -p test_sort_postgres_fixture.py -v
pnpm --dir backend typecheck
pnpm --dir backend test -- asset-serial.postgres.spec.ts
```

The last command must report four skipped cases without live opt-in. Live execution
passed four scenarios in a separately approved synthetic run; do not treat default
skips as passed or change flags to bypass approval. The owned container was stopped
and retained with its volume. HTTP/HTTPS and native acceptance remain pending.
