# Daily runtime base recovery harness

Status: base-profile synthetic recovery accepted; full-profile daily deployment pending.

`daily_local_recovery.py` provides an injected recovery verifier for the base
profile (migrations 001/002 only). It is not a CLI or production backup tool.
The caller must provision two distinct labeled synthetic databases, stop writers,
supply a bounded command adapter and deadline, and own cleanup. The restore
target must be fresh and unmigrated. Source table names must match the two base
tables exactly; this check alone does not attest their schema versions. No automatic retry or cleanup is performed.

The verifier rejects existing artifacts and nonempty targets, preserves a custom
PostgreSQL dump and checksum, compares all account/asset columns as hashes, and
requires an explicit restored-target login check before writing a success manifest.
Failure retains available artifacts without a success claim. Reports omit rows,
password hashes, credentials and connection strings. Dumps contain private data;
use only synthetic data until private storage access is separately accepted.

Offline tests inject all commands. They do not prove SQL syntax, PostgreSQL restore,
TLS, login, or process cleanup. A concrete bootstrap runner and separate approval
are still required before any live fixture. Optional domains, receipts, dates,
location, check dates and saved filters are not covered by this base-only slice.
Do not treat it as full-profile daily backup acceptance.

See [daily-use prerequisites](daily-local-use-plan.md).

## Lifecycle integration source

`daily_local_recovery_acceptance.py` orders source provisioning/seed, writer
shutdown, restore and target login, then attempts ownership-checked cleanup of
both databases even on failure. `daily_local_recovery_sessions.py` connects the
real launcher/gateway and synthetic HTTPS client; only the Python inert app is
accepted. Sessions are retained before startup, including failed startup attempts.
A future entrypoint must always call `close_all()` on the retained session factory,
including when `open()` fails. The CLI bootstrap exists but no live recovery is certified yet.
The verifier manifest covers dump/data/login only; successful whole-fixture
acceptance additionally requires all cleanup and listener-release checks.

## Opt-in bootstrap (not executed)

`daily_local_recovery_fixture.py` requires `--execute-synthetic`, an absolute
`--candidate` under `backend/.local/daily-candidates/`, a pinned existing `--image`,
absolute `--cert`/`--key` references, and four distinct non-reserved ports:
`--db-port`, `--restore-port`, `--backend-port`, `--tls-port`.
It creates two fresh labeled synthetic databases and one new evidence directory.
Only source receives migrations 001/002; restore target is initially empty.
The acceptance deadline is 120 seconds, with a separate 45-second command cleanup
allowance. Session shutdown retains its own bounded graceful-close timeout.
If session cleanup fails, databases are preserved rather than stopped underneath
possibly active owned processes. Containers, volumes, dumps and failure evidence
are never deleted. The result is successful only after cleanup and free-port checks.
No build, image pull, automatic retry, real app or ordinary database is allowed.

The default offline group now contains 108 tests. A separately approved live run
is required to validate actual dump/restore, restored login and cleanup behavior.

## Approved synthetic acceptance

One separately approved fixture completed with the existing backend candidate:
custom-format dump, independently rechecked SHA-256, identical full-column
account/asset snapshots in the restored target, and HTTPS login/read acceptance.
The synthetic source contained one account and one asset. The final result reports
cleanup stopped after session shutdown and all four listener-port release checks.
Containers, volumes and dump were retained; no automatic retry was performed.

This proves only migrations 001/002 through an inert Python app substitute.
It does not certify optional domains, real Flutter, private storage permissions,
backup scheduling/retention, or a production/daily deployment. Earlier offline-only
statements describe source development checkpoints, not a full-profile acceptance.
