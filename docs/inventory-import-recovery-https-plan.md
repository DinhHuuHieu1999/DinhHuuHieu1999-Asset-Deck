# Import recovery HTTPS acceptance plan

Status: source harness implemented and offline checks passed; one separately approved isolated fixture completed. No deployment or Windows
app build was performed.
The earlier import HTTPS acceptance does not prove recovery from a saved file.

## Required proof

Use the real Dart API client and recovery codec against a new marker-owned
synthetic PostgreSQL/backend/HTTPS fixture. Keep default TLS validation. Reuse
existing lifecycle ownership, explicit import profile and bounded cleanup rather
than introducing a second production server or dependency.

1. Register two synthetic owners. Create one source asset and prepare an immutable
   import for the other owner with a new UUID v4.
2. Explicitly write the recovery envelope to a new private fixture file using
   exclusive creation. Verify exact bytes and SHA-256 independently. Never
   overwrite, print its contents or store credentials in the envelope.
3. Submit once. A test-only fault must forward the exact import and wait for the
   complete successful upstream response before suppressing that response to the
   client. Record only fault activation and response status, not private bodies.
   A failed connection before forwarding is not proof of lost acknowledgement.
4. Confirm the client reports an uncertain outcome and the fixture database has
   exactly one matching receipt and one imported asset. Preserve the returned
   IDs only in the private evidence needed for comparison.
5. Terminate the submitting Dart process. Launch a separate process without its
   draft/session objects. Reauthenticate the same synthetic account, load the
   saved file and validate the current configured endpoint/account. Selection
   and validation must not submit any request.
6. Require a new explicit replay action with the restored exact request/key.
   Compare original receipt IDs and full editable asset fields before/after;
   asset and receipt counts must not increase. A second generated key is failure.
7. Verify owner mismatch and endpoint mismatch fail locally without import
   traffic. Confirm the other owner and original source asset remain unchanged.

## Harness boundaries

- The fault is opt-in, test-only, fixed to the exact import POST and one selected
  operation. It is never enabled by the ordinary import/native fixture profile.
- Reject malformed fault configuration before listening or reading TLS material.
  No generic request interception, arbitrary route, automatic retry or production
  middleware changes.
- Both processes must verify the same fixture marker before account/data access.
  Use private local control files for synthetic credentials; do not pass secrets
  on command lines or include them in public output.
- Keep the existing global deadline and finite per-process/network timeouts.
  Poll the same live process handle; an observation timeout must not launch a
  replacement fixture.
- Stop only identity-verified resources; retain database volume, recovery file and
  evidence. Do not change regular endpoints, trust, firewall or Smart App Control.

## Offline review before execution

Add regressions for disabled-by-default fault routing, one-shot scope, upstream
success-before-disconnect, bounded cleanup and exact stage result validation.
Test fail-closed prerequisites before any subprocess/resource creation. Review
process reconstruction separately from in-process widget reconstruction.

Execution requires separate approval after source/tests pass. This fixture does
not replace Windows dialog/launcher acceptance or security coverage review.

## Current offline evidence

- 25 Node tests: proxy/fault selection, explicit dedicated CLI, default-profile
  isolation, bounded routing and success-before-disconnect conditions.
- Eight Python recovery tests: exact stage invocation/results, missing prerequisites,
  mocked success, missing fault confirmation, changed rows, proxy-stop timeout and redirect refusal.
- Three Dart driver contract tests: fixture-only arguments, exclusive file writes
  and bounded UTF-8 reads. Driver analyzer passed. These tests do not run its HTTP
  stages; full source/process behavior requires the live fixture below.
- Existing lifecycle cleanup tests remain separate evidence. No new container,
  listener, TLS file read or actual driver process was executed in this phase.

The runner is `scripts/recovery-https-fixture.py`. Its `--execute-synthetic`
flag and explicit image/TLS/executable/port arguments remain mandatory. It reuses
existing lifecycle cleanup and deadline controls and keeps all synthetic output.
The private control file contains synthetic credentials; the recovery envelope
itself does not. Neither file belongs in Git or chat.

## Isolated live acceptance

One approved run completed without retry using the existing backend candidate and
PostgreSQL image, default localhost TLS validation and new synthetic resources.
The fault marker confirmed a complete successful upstream response was suppressed.
A separate Dart replay process reauthenticated, read the retained recovery file,
rejected owner/endpoint mismatches, and returned the existing asset ID. Full asset
and receipt row snapshots were identical before/after replay; the source owner's
asset was unchanged. Python independently matched the envelope checksum.

The runner reported `completed` and cleanup `stopped`. The exact fixture container
was independently observed as exited with its matching ownership label, and all
three selected loopback ports had no remaining listeners. Synthetic files and
volume were retained. This proves this isolated HTTP/process scenario, not
Windows dialogs, crash-durable filesystem writes, native UI or security coverage.
