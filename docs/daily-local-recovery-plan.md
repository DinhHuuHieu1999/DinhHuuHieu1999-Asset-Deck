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
TLS, login, or process cleanup. The opt-in bootstrap runner has completed the separately approved synthetic
acceptance described below. Optional domains, receipts, dates,
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
including when `open()` fails. The CLI bootstrap passed base-profile synthetic recovery as recorded below.
The verifier manifest covers dump/data/login only; successful whole-fixture
acceptance additionally requires all cleanup and listener-release checks.

## Opt-in bootstrap boundary

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

The offline group contains 110 tests, also verified from selected committed source
with network and subprocess calls blocked. Actual base-profile dump/restore,
restored login and cleanup were checked separately in the approved fixture below.

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

## Extended verifier source (offline only)

`verify_extended_restore` reuses the bounded base verifier with a separate
`daily-extended` dump/manifest namespace. It requires the four tables from the
named extended profile, nonempty accounts/assets/saved filters and empty import
receipts. Snapshots include every column and use row JSON ordering because
receipt rows have a composite identity, not an `id` column. Only hashes/counts
are written to the manifest. Snapshot table sets are restricted to the two fixed
profile contracts before any ownership query or command execution.

The existing base wrapper keeps its table and artifact contract. Nine additional
injected tests cover extended success, missing tables/filter seed, unexpected
receipts, changed optional data and failed restored login. The worktree daily
offline group now has 127 tests. No extended SQL/HTTPS fixture has run. The recovery bootstrap can select this
verifier explicitly as described below; normal launcher defaults are unchanged. A future callback must check
restored optional fields and owner-scoped saved filters, not just login.

### Synthetic migration adapter

`SyntheticDatabase` now accepts a named profile, defaulting to base. The extended
profile selects the fixed ordered 001-007 list; it does not enable import APIs.
All selected SQL files are loaded and checked for empty/oversized content before
any database command. Ownership is checked again before each migration. No
arbitrary SQL path or profile is accepted. Five injected tests cover ordering,
missing/empty artifacts, invalid profile and ownership changes. The current
worktree daily group has 132 offline tests.

The existing bootstrap still uses base by default. Extended session integration
is described below; extended live acceptance has not run.

### Extended HTTPS client source

`daily_local_extended_client.py` seeds two synthetic owners through normal
HTTPS/auth/CSRF routes. One asset has explicit dates/location/check date; the other
has explicit null fields. Each owner receives one saved query. Source and restored
checks compare exact owned asset values and saved-query results and expect 404
for the other owner's optional-field reads. The shared transport now accepts an
explicit PUT method with the same fixed TLS endpoint and CSRF headers.

Eight new offline tests bring the worktree daily group to 140. They use fake
responses and do not prove backend behavior. Session/bootstrap source integration is described below; a separately scoped
extended live fixture remains pending.

### Opt-in profile integration (not executed)

The recovery bootstrap accepts `--profile inventory-with-saved-filters`, retaining
`base` as its default. The selected profile reaches both synthetic databases,
backend environment, extended HTTPS client and restore verifier. Extended session
startup rejects a database profile mismatch. Preflight requires the selected
migration and adapter artifacts before creating an evidence directory.

Four additional integration tests bring the daily offline group to 144. They
verify adapter selection, flag propagation, missing artifacts and invalid profile
rejection using fake processes/commands only. Existing base orchestration tests
still pass. No extended database, certificate read, backend process or fixture was
started for this source change. Real extended acceptance requires a separately
approved run; the normal daily launcher has not been rolled out.

## Extended live attempt and diagnostics

One approved extended fixture retained a valid custom-format dump but did not
produce a success manifest. Its redacted report was too coarse to distinguish
restore, comparison and target-login failure; no root cause is claimed yet.
Both new containers were independently observed exited and all four ports were
released. No automatic retry was performed.

The bootstrap now records fixed lifecycle/verifier checkpoint labels and elapsed
seconds in its existing result artifact. It does not copy exceptions, command
output, credentials or row data. Two new offline tests and the failure-report
regression bring the group to 146 tests. Diagnostic source is not a successful
extended recovery acceptance; another live attempt requires separate approval.

### Per-request diagnostic source

The subsequent approved diagnostic attempt passed dump, restore and snapshot
comparison, but failed during the target-login check. Source seeding took about
84 seconds; the original 120-second acceptance deadline remains unchanged.
This does not prove the cause of the login failure or successful recovery.

The synthetic client now retains bounded per-owner request timings (at most 256
entries per owner), with fixed outcome categories only. The final result includes
these timings even after acceptance failure. No paths, IDs, headers, credentials,
response bodies or exception text are included. Transport errors, response
mismatches and invalid JSON are not marked completed. Offline regression tests
cover timing, redaction, bounds and failed-run report retention. No additional
live run is implied; another fixture requires separate approval.

### IPv4 fixture transport

A closed-port TCP diagnostic resolved localhost to IPv6 first, then IPv4. Two
localhost attempts took about 4.11 seconds each, versus 2.04 seconds for IPv4
alone. Combined with the IPv4-only gateway and approximately 2.08 seconds on
almost every successful HTTPS request, this identifies address fallback as a
likely repeated delay, not proof that all recovery checks will pass after a fix.

The synthetic client's HTTPS handler now connects only to 127.0.0.1 while keeping
localhost as the URL, Host header and TLS server name. Default certificate and
hostname verification remain enabled; proxies and redirects remain disabled.
The override is scoped to this fixture client, not global socket resolution.
Offline tests exercise the real HTTPS connection wrapper with fake sockets and
assert IPv4 routing, localhost SNI, verification settings and foreign-host
rejection. The deadline and required assertions are unchanged. A new live run
is still pending separate approval; this is not deployment acceptance.

### Extended synthetic acceptance after IPv4 correction

The separately approved single run completed the extended profile in about 31
seconds without increasing the 120-second deadline or removing assertions. Both
owners retained their assets, populated/null optional fields and saved queries
after restore and reauthentication. Full-column source/target snapshots matched:
two accounts, two assets, two saved filters and zero import receipts. The retained
custom-format dump hash was independently checked against the success manifest.

All 60 measured API requests completed; median duration was about 0.028 seconds,
with the slowest below 0.4 seconds. This supports the IPv6-first connection
fallback diagnosis for the earlier repeated delay. The two fixture containers
were independently observed stopped, and a subsequent listener check found the
four fixture ports free. No automatic retry, normal-database change, deployment,
Windows security change or native Flutter acceptance was performed. Earlier
pending statements describe historical source checkpoints, not the latest run.
Codacy API authorization remains unresolved; empty local responses are not PASS.
