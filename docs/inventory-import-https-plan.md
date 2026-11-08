# Inventory import HTTPS acceptance plan

Status: source/offline checks and one separately approved HTTPS acceptance run
completed. This document does not authorize further execution. PostgreSQL
repository acceptance passed separately.

## Reuse boundaries

Reuse the existing owned lifecycle in `scripts/client-https-fixture.py` and its
fixed-upstream TLS proxy. Keep the default client/export fixtures unchanged:
import must be an explicit optional fixture mode, disabled by default.

Before this change, the proxy did not allow `POST /api/v1/assets/import`. Its 1 MiB body
limit is already suitable; do not increase it or allow arbitrary API routes.
The original lifecycle applied only migrations 001/002 without enabling import.
The new import mode uses a validated, fixed migration/flag profile rather
than accepting arbitrary SQL paths, child environment overrides or callbacks
from command-line input. Include migration 003 in source hashes only for import.

## Offline preparation and checks

- Proxy import mode allows only the exact POST import path; default denies it.
  Preserve fixed loopback upstream, existing deadlines and response/body limits.
- Preflight requires migration 003, import driver and reviewed candidate artifacts
  before resource creation. Reject missing prerequisites without subprocesses.
- Import mode sets `ASSET_IMPORT_ENABLED=true` only in the synthetic backend child;
  ordinary fixtures remain disabled. Never load real app env files.
- Database readiness must use TCP and verify database/user identity. Keep bounded
  commands, total deadline, exact resource ownership and independent cleanup.
- A Dart driver must use the real `AssetApi` and default certificate validation.
  Verify the existing random fixture marker before registration or mutation.
- Unit tests inject fake runtimes/transports; they must not start Docker, bind
  ports, read TLS material or contact a backend. Assert default-mode compatibility.

## Proposed live acceptance, separately approved

Build one backend candidate with installed dependencies and record source/output
hashes. Use one new synthetic PostgreSQL container/volume, existing immutable
image without pull, and three distinct loopback-only ports. Reference an existing
localhost certificate/key without copying, logging or changing trust.

Apply migrations 001/002/003 only to that fixture. Register two synthetic owners
through HTTPS and use the real Dart API client to verify:

1. A validated snapshot prepares a draft without modifying inventory.
2. Explicit import succeeds and returned IDs match the target account inventory.
3. Replaying the identical draft returns identical IDs without additional assets.
4. Same request key with changed content conflicts without partial writes.
5. A second owner cannot use the first owner's account-bound draft or observe its
   assets; a new draft bound to the second owner imports independently.
6. Missing authentication/CSRF and invalid or oversized input are rejected without
   writes. Distinguish proxy rejection from backend rejection in evidence.
7. Client session invalidation does not silently retarget an operation.

Do not force COMMIT failures through the public API: repository fault injection
has separate evidence. Do not claim HTTPS proves process-loss recovery, Windows
native interaction, accessibility, backup/restore or deployment readiness.

Run once with bounded scenario and cleanup deadlines, no automatic retry. Stop
only exact owned processes and label-verified container, confirm listeners close,
and retain volume/evidence. Report counts, IDs only as needed for assertions and
sanitized outcomes; never emit credentials, tokens, full payloads or TLS keys.

## Remaining decisions

Persistent client recovery is not implemented. The current RAM-only draft must
remain explicit in documentation and acceptance results. Native tests remain a
separate gate and must not disable or bypass Smart App Control.

## Prepared source and current verification

The proxy has an exact opt-in import route and validates the optional
`--import-enabled` CLI flag before reading TLS files. The lifecycle selects a
fixed three-migration profile only for import, sets the backend child flag and
requires a dedicated acceptance callback. Existing default/export/native modes
remain separate.

`scripts/import-https-fixture.py` is the only import entrypoint. Its CLI requires
`--execute-synthetic`, immutable `--image`, absolute `--cert`/`--key`, SDK `--dart`
and distinct `--db-port`/`--backend-port`/`--tls-port`. It does not build or install.
Do not run it until a separate build and execution scope is approved.

`flutter/tool/import_https_acceptance.dart` uses the real API client and the
existing fixture-only Python SHA-256 bridge. It verifies import, exact replay,
changed-content conflict, account-bound refusal, independent same-key owners and
sign-out invalidation. A separate synthetic account exercises negative HTTP
cases, so there are three synthetic accounts in total; the Dart result's two
owners refer only to its own scenario. Rejected requests must leave aggregate
asset/receipt counts unchanged. Counts alone are not a full database-integrity
hash or a proof against arbitrary value-only mutations.

Offline checks passed: 15 stream proxy tests, 16 lifecycle tests, 12 import runner
tests, 11 export and 11 native-runner regression tests. The Dart driver analyzes
cleanly. Transport tests use fake responses and prove marker-before-write,
auth/CSRF header separation and fixed rejection statuses without networking.
These results do not prove the scenarios pass through real HTTPS.

One separately approved backend build completed. The first HTTPS fixture reached
the acceptance callback but failed without sufficient diagnostic detail; its
owned processes/container stopped and volume was retained. No acceptance is
claimed. The import runner now records fixed stage labels, request indices,
expected/observed statuses and a certificate-verification boolean only. It rejects
unknown/private checkpoint fields. No credentials, URLs, response bodies or raw
exception text are persisted by checkpoints. A new execution requires approval;
the existing reviewed backend candidate can be reused without rebuilding.

## Oversize response diagnostic

The second approved HTTPS run stopped at request 9 (the proxy oversize case),
before an observed 413 and before the Dart driver. Its container stopped and
volume was retained. This narrows the failure but does not prove full HTTPS
acceptance.

An offline regression reproduced request destruction before response `finish`.
The test proxy now uses a non-destroying request iterator, pauses the rejected
request and destroys it only after the 413 response finishes. The iterator change
also avoids implicit destruction when leaving the read loop early. The size
limit and no-upstream-on-oversize contract are unchanged. Sixteen proxy tests and
12 import-runner tests pass. Real TLS delivery after this repair remains pending;
a new isolated run needs approval and can reuse the existing backend candidate.

## Successful HTTPS follow-up

A separately approved new fixture completed after the oversize repair, reusing
the existing backend candidate without a rebuild. HTTP 413 arrived correctly;
all negative statuses/count checks and the real Dart import/replay/conflict,
two-owner, account-binding and sign-out scenarios passed. The independent
negative-client account makes three synthetic accounts total. Cleanup completed
and Docker subsequently reported the matching-label container stopped.
No runtime or database outside the fixture was changed. Native interaction,
process-loss recovery, backup/restore and security coverage remain separate gates.
