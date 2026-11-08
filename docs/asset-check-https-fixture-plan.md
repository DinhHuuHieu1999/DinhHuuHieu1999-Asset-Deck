# Manual check-date HTTPS acceptance

Status: source and offline contracts only; execution requires separate approval.

## Scope

Build the backend candidate using existing dependencies, then run exactly one
`scripts/check-https-fixture.py` execution. Use an already available PostgreSQL
image pinned by digest, a new synthetic database/container/volume, three distinct
loopback ports and existing localhost TLS material. Never pull, install, retry,
change trust/firewall or use the regular backend/database.

The runner requires `--execute-synthetic`, `--image`, `--cert`, `--key`, `--dart`,
`--db-port`, `--backend-port` and `--tls-port`. Paths and ports must pass the
existing shared preflight. Missing compiled check-date artifacts refuse execution
before resources are created. Do not read TLS material before run approval.

The shared runtime has a 300-second overall deadline and a maximum 120 seconds
per command. Cleanup verifies ownership, stops owned processes/container and
retains synthetic data and evidence. A cleanup failure is not acceptance.

## Required checks

- Default TLS verification and exact synthetic identity marker before registration.
- Anonymous read rejected; CSRF-less write rejected. Successful writes use the
  real Dart client authentication/CSRF flow.
- Two owners remain isolated; stale shared versions conflict without retry.
- Check-date updates preserve base fields, purchase/warranty dates and location.
- Unknown-date filtering combines with literal search and exact location;
  clearing a date returns the matching asset to the result.
- Sign-out prevents subsequent client reads.
- Exact typed success output and unchanged selected source/artifact hashes.

The proxy enables check-date GET/PUT only for its dedicated profile. Import and
selection-export capabilities remain off. Existing profiles must remain unchanged.

## Evidence and limits

Offline checks cover strict profile selection, missing artifacts before side
effects, exact result validation, migration/env/proxy dispatch and route bounds.
They do not establish real HTTPS or database acceptance. PostgreSQL repository
acceptance is recorded separately in the repository fixture plan.

Windows UI, restart/restore, deployment and commit are outside this run. Codacy
empty output is not verified coverage or a security pass. No rollback of the
regular service is needed because it is not changed.

## First isolated execution

The approved backend build succeeded. One HTTPS fixture stopped at the
anonymous/CSRF check, before synthetic account registration. Cleanup reported
`stopped`; evidence is retained in
`.local/asset-client-3377bce79be498d9424a60f8da5f0bf4/`.

Root cause: the proxy handler omitted forwarding its check capability to the
route allowlist, so it returned 404 before contacting the backend. A stream-level
regression reproduced zero upstream calls with capability enabled. The handler
now forwards the capability; the regression verifies exact GET/PUT dispatch and
preserved upstream 401/403 responses. No automatic retry was performed. Real
HTTPS acceptance remains pending a separately approved execution.

## Verified execution after proxy correction

One separately approved fixture using the existing backend candidate completed
without retry. The real Dart client passed the required flow; exact typed output
and selected source/artifact hashes matched. The report records `completed`,
`checkDateDartClient: true`, `cleanup: stopped` and native acceptance `pending`.
Docker independently confirmed the owned container is exited. Evidence and
synthetic data remain in
`.local/asset-client-bf3cbbbd34189797223b420eefb17a14/`.

This establishes the scoped HTTPS/client flow, not Windows UI, restart/restore,
rollout, commit approval or Codacy/security coverage. The regular service and
its database were not changed.
