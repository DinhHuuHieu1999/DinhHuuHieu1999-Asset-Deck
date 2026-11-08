# Import v3 recovery HTTPS acceptance plan

Status: one separately approved synthetic recovery HTTPS fixture completed.
Native dialogs and UI acceptance remain pending.

## Contract

Reuse the isolated import-v3 lifecycle and existing backend candidate. No schema,
production endpoint, dependency or automatic retry is added. The dedicated runner
is `scripts/recovery-v3-https-fixture.py`; its Dart driver runs three distinct
processes, with default TLS verification and exact fixture-marker checks.

1. Prepare: create synthetic source/target owners and one asset with dates and
   location; export v3, prepare a target-bound request and save its private recovery
   envelope exclusively. Save synthetic login control separately, never in output.
2. Independently verify the envelope SHA-256, schema 3, operation, account, endpoint
   and request key before replacing only the exact owned proxy child.
3. Submit once through a dedicated one-shot fault proxy selecting exact POST
   `/api/v1/assets/import/v3` and request key. Suppress only a complete successful
   upstream response. The client must report uncertain delivery, not success.
4. Confirm marker `claimed=true/suppressed=true` and database counts of two assets
   and one receipt. Snapshot all asset/receipt rows before explicit replay.
5. Start a fresh Dart process, login to the same target, parse the saved envelope,
   reject wrong endpoint/account, then explicitly replay the same request/key.
   Require identical IDs, base fields, dates, location and versions. Independently
   require the database row snapshot to remain byte-identical across replay.

Private recovery files are bounded to 2 MiB; request bodies retain their separate
1 MiB bound. Checksums are integrity checks, not authenticity or encryption.
Synthetic credentials remain only in local ignored fixture control files; no
payload, token or error body belongs in committed logs or stdout summaries.

## Safety and compatibility

A normal fixture never injects a fault. Only the dedicated recovery CLI accepts
`--lose-import-ack` and its explicit key; ordinary CLI rejects extra arguments.
V1/v2 selectors cannot claim v3 routes, and v3 cannot claim v1/v2 or route aliases.
Failed or incomplete upstream responses are not suppressed. Existing profiles and
contracts remain unchanged. Missing artifacts, binding mismatch, corrupted digest,
wrong marker, unexpected counts or mutated rows fail closed without replay/retry.

A future execution requires separate approval: new synthetic container/volume,
three distinct preflight-checked loopback ports, an existing pinned image and TLS
material. No pull, install, build, real account/database, trust/firewall/SAC change
or Windows app. The total execution budget is 300 seconds with separate bounded
cleanup. Ownership is checked before stopping; all fixture data/evidence is kept.
This is process reconstruction after response loss, not a backend restart or
backup/restore drill. Native file-dialog acceptance remains separate.

## Offline verification

```powershell
python -B -m unittest discover -s scripts -p 'test*https_fixture.py' -q
node --test scripts/client-https-proxy.test.mjs scripts/import-recovery-fault.test.mjs
```

Python tests mock process/network boundaries, including checksum/binding failures,
proxy stop timeout, unconfirmed fault and row mutation. Node tests use streams,
not TLS listeners. Dart driver tests exercise arguments, exclusive writes and
bounded reads; recovery parser tests cover exact request bytes, binding and limits.
None of these offline checks count as live HTTPS recovery acceptance.

## Observed isolated acceptance

Fixture `d7e0221f78a428139d6dcbcf2b50f24a` completed using the existing backend
candidate, without retry. A complete successful import response was suppressed;
a fresh Dart process reconstructed the private request and replayed it explicitly.
Asset and receipt snapshots remained identical, including dates and location.
The runner reported `processReconstruction`, `lostAcknowledgement` and
`unchangedRows` as true. Independent inspection confirmed the labeled container
was stopped and its matching volume retained, with only a loopback database port.
Evidence remains in the ignored fixture directory. This does not establish native
dialog, disabled-route, backend restart, backup/restore or deployment acceptance.
