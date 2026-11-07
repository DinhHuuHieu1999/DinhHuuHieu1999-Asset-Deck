# Daily runtime synthetic acceptance plan

Status: separately approved synthetic HTTPS/restart run completed; deployment remains pending.

## Purpose

Exercise the new daily launcher and gateway, not the old fixture proxy. Keep
ordinary inventory, accounts, configuration, and PostgreSQL instances untouched.
Do not claim daily deployment or backup acceptance from this fixture.

## Proposed scope

- Build a separate backend candidate from the reviewed source using installed
  locked dependencies, without installing packages or changing lockfiles.
- Create one synthetic PostgreSQL container and volume from an existing approved
  image, without pulling or mounting real data. Bind one database port to loopback.
- Use new loopback HTTP/HTTPS ports selected after an availability check. Reuse an
  existing suitable localhost certificate by reference only; do not change trust,
  firewall rules, or Smart App Control.
- Apply only the reviewed account/inventory migrations to the new database.
  All optional feature flags and imports remain off for this first transport test.
- Run the real backend supervisor and new gateway with synthetic secrets and an
  isolated session directory. Use a fixture-owned inert GUI substitute to exercise
  lifecycle ownership; do not open or build Flutter in this first fixture.
- Keep a 120-second acceptance deadline, no automatic retry, and a separate bounded
  cleanup allowance. Stop if image, TLS, port, or resource ownership checks fail.

The inert GUI substitute does not certify Windows native application behavior.
Its use must be explicit in the runner and result, never hidden as app acceptance.

## Assertions

1. Start emits readiness only after the owned backend and HTTPS gateway are ready.
2. Default TLS validation succeeds through the new gateway; no insecure client flag.
3. Register/login, CSRF, and a synthetic inventory create/read request work through
   HTTPS. Verify the saved row belongs to the synthetic account.
4. Missing/duplicate/non-local Host and invalid framing are rejected without
   forwarding. A busy port causes no child start or listener termination.
5. Close the inert GUI substitute, then stop. Confirm the owned backend and gateway
   exit, listener ports are released, and the session lock is released.
6. Start again against the same synthetic database, sign in, and verify the asset
   remains. Close the substitute and stop again within the same bounded run.
7. Preserve generic event labels, durations, resource IDs, artifact hashes, and
   assertion results only. Do not include credentials, cookies, request bodies, or
   database connection strings in the public result.

Slow-request and stalled-upstream timeout tests should use separately bounded
synthetic peers. If the overall deadline cannot cover them, keep them explicitly
pending rather than silently extending or retrying the fixture.

## Cleanup and retained evidence

Verify container labels and process/session identity before stopping resources.
Never kill a process discovered only by port or PID. If graceful shutdown fails,
report incomplete cleanup and retain the ownership evidence; do not force-kill or
delete a lock automatically. Stop the verified fixture container and retain its
volume, configuration, and redacted evidence under ignored local storage.

Do not import the synthetic inventory into a daily database. Do not provision a
persistent daily runtime, install a service, schedule backups, commit, or push.

## Before execution

`scripts/daily_local_acceptance.py` now defines the two-start acceptance sequence
with injected lifecycle, lock, HTTP client, and inert-substitute closer. Four
offline tests cover persistence sequencing, startup/HTTP failure cleanup, and
retaining the lock when cleanup fails. This driver alone cannot provision a
fixture or certify any real service; the concrete fixture entrypoint is pending.

`daily_local_fixture_client.py` adds the synthetic HTTPS client: default TLS
validation, no environment proxy or redirects, normal registration/CSRF/login,
same-record verification after restart, and raw Host rejection checks. Four fake
client tests pass; no HTTPS request has run. The complete offline Python group now
contains 70 tests.

`daily_local_fixture_database.py` now implements the synthetic database adapter:
existing image pin, fresh labeled volume/container, loopback-only port, role/DB
readiness identity, fixed base migrations, and ownership-checked stop without
deletion. Five command-contract tests bring the Python total to 75. Docker has not
been called.

The concrete entrypoint is `scripts/daily_local_fixture.py`. It requires
`--execute-synthetic`, an immutable `--image`, an absolute `--candidate` directory
under `backend/.local/daily-candidates/`, absolute `--cert`/`--key` references, and
three distinct explicit `--db-port`/`--backend-port`/`--tls-port` values. It reuses
only the existing bounded subprocess adapter, not the legacy fixture proxy or its
force-kill cleanup. Six entrypoint tests bring the Python total to 81; all runtime
adapters are fake in those tests.

The inert app substitute is the existing Python executable with its stdin kept
open, not a Flutter window. Closing that private stdin ends the substitute before
the real backend/gateway graceful stop. Reports explicitly exclude native acceptance.

Prepare and offline-test the bounded fixture runner, including failure cleanup and
resource ownership. Then obtain explicit approval for one candidate build and one
run with the selected ports, image, and TLS references. No fixture has run yet.

See the [daily-use plan](daily-local-use-plan.md) for remaining deployment gates.

## Latest execution review

One separately approved backend candidate build succeeded. The first synthetic
fixture failed before its first acceptance event. Its retained result reports
cleanup stopped; read-only Docker inspection confirms the container exited.
The original report cannot identify the failing stage, so HTTPS and restart
acceptance remain unproven. No second fixture has run.

The runner now records fixed stage labels without exception text or secrets.
Readiness also detects an exited child without waiting for the full deadline.
The updated offline group passes 82 tests. These diagnostic changes have not
been exercised against a live fixture. Earlier source-only counts and statements
above describe their historical checkpoints, not current runtime acceptance.

## Successful synthetic restart acceptance

A later separately approved run completed using the existing backend candidate
and corrected fixture login contract (`identifier`, not `email`). Its result
contains `first-start`, `first-stop`, and `restart-persistence`, with cleanup
reported stopped. Default TLS, normal account/CSRF requests, asset creation,
Host rejection, and the same asset after restart passed through the new gateway.
The CRLF readiness regression is fixed and the offline Python group passes 84 tests.

This does not certify Flutter: the app process was an inert substitute. Backup,
restore, slow-peer draining, live malformed-framing and busy-port assertions,
private-directory access, and daily deployment remain pending. No regular
backend/database was updated and no commit or push is implied. Earlier failures
remain retained evidence, not successful runs.
