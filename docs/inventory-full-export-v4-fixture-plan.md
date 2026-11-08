# Full export v4 PostgreSQL acceptance plan

## Scope and approval boundary

The operator-approved isolated run passed all four repository scenarios.
Container ownership and stopped state were independently verified afterward.
Container and volume were retained; no regular database was accessed.
Future executions still require separate operator approval.
The fixed `scripts/export-v4-postgres-fixture.py` entry uses the existing owned
repository lifecycle; importing it does not start processes or create resources.
No backend server, HTTPS, native app or regular database is involved.

## Planned isolated run

- Existing immutable PostgreSQL image ID only; no pull or dependency installation.
- New synthetic container, named volume, database and two accounts.
- One random port bound only to 127.0.0.1; no regular database ports or host-data mounts.
- Existing migrations 001 through 006 applied only inside the synthetic database.
- Total execution deadline 120 seconds; one Jest invocation, no test retry.
- Verify ownership before stopping; retain stopped container, volume and evidence.
- Cleanup has its own bounded 30-second allowance. Cleanup failure is not acceptance.

## Four required repository scenarios

1. Empty/nullable export and exact extreme dates, location and manual check date;
   recompute SHA-256 from the serialized payload.
2. All 51 owned rows, exclusion of a second account and unchanged database rows.
3. Complete 500-row export and explicit refusal at 501, never truncated success.
4. An observed advisory-lock barrier around a concurrent committed edit proves
   base fields, dates, location and manual check date come from one SQL snapshot.

Skipped, partial or malformed Jest results fail the lifecycle acceptance gate.
The suite defaults to skipped and refuses non-loopback/unmarked database targets.

## Offline verification

```powershell
python -B -m unittest discover -s scripts -p test_export_v4_postgres_fixture.py -v
pnpm --dir backend typecheck
```

Six new lifecycle tests and 99 shared PostgreSQL-harness regression tests passed.
Without opt-in, the four database cases were confirmed skipped. The separately
approved PostgreSQL run subsequently passed all four, with zero skipped or
failed assertions. Real HTTPS, Windows and Codacy acceptance remain pending.
