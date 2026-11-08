# Inventory import Windows acceptance plan

Status: source/offline preparation and a separately approved Windows release
build completed. Operator checks on isolated HTTPS fixtures confirmed import from
one to two assets, persistence across sign-out/sign-in, unsent Keep/Discard and
file-picker cancellation preserving preview. This document authorizes no runs.
Original-asset field comparison and native fault-path checks remain unconfirmed.

## Finding

The existing native runner validates endpoint and deployment hashes but has no
import compile-flag contract. Its seed creates one ordinary asset and does not
prepare an import file. Reusing an old executable or merely enabling the backend
cannot prove that native import navigation exists.

## Minimal source preparation

Keep ordinary native mode unchanged. Add a separate explicit import profile that:

- Requires a release candidate manifest with the expected endpoint and explicit
  `ASSET_DESK_ENABLE_IMPORT=true` build metadata, plus exact deployment hashes.
  Metadata records the build contract; it does not replace manual UI acceptance.
- Uses the reviewed three-migration backend/proxy import lifecycle.
- Seeds one synthetic operator account and exactly one existing asset over TLS.
- Prepares a valid one-record synthetic inventory export using the existing
  snapshot/checksum contract and an actual SHA-256 implementation. Give it a
  distinct name such as `Synthetic native imported asset`.
- Writes credentials and the synthetic file only under the owned ignored fixture
  folder, never stdout/chat/tracked source. No real inventory file is needed.
- Launches only the verified candidate once and holds its exact owned services for
  at most 30 minutes. Stop safely on exit, deadline or service failure and retain
  the synthetic database/volume. Never bypass Smart App Control or alter trust.

Offline tests must refuse missing import metadata, wrong endpoint, missing or
changed deployment files, malformed seed/export and missing explicit opt-in
before launch. Existing native tests must continue passing.

## Operator checks after separate execution approval

1. Sign in with the new fixture account. Confirm one existing asset.
2. Open the separate Import page, select the synthetic export, and verify one new
   asset in preview, correct account and editable fields. Preview must not write.
3. Enter the review step, acknowledge and confirm exactly once. Refresh inventory:
   two assets total and the distinct imported name should appear.
4. Check the original asset is unchanged. Sign out and sign back in to the same
   fixture account, then refresh: both saved assets remain.
5. On a fresh unsent preview, Back offers Keep/Discard. Canceling the file picker
   preserves the current draft. Do not confirm a new operation merely to test UI.

Do not claim a file export is authentic merely because its checksum matches.
Do not claim replay/unknown-outcome native handling from successful confirmation
alone; those require separate controlled fault tests. Keyboard, screen reader,
200% text and process-loss recovery each retain explicit acceptance status.

## Recovery limitation

The earlier native candidate retained its import key/draft only in RAM. The new
[recovery candidate](inventory-import-recovery-proposal.md) requires an explicit
private recovery file before submission. Its isolated HTTPS process-reconstruction
check passed, but the Windows recovery controls have not yet been accepted. Never
apply the historical import acceptance to the new recovery controls or advise a
new key blindly after an uncertain write.

## Prepared runner and offline evidence

The existing native entrypoint now accepts `--import-mode` in addition to its
existing explicit native/synthetic flags. The profile requires candidate metadata
`buildDefines: {"ASSET_DESK_ENABLE_IMPORT": "true"}` and the exact deployment
inventory/endpoint before launching. Default native mode still needs no import
metadata and creates no import file. The lifecycle enables import only in that
profile and applies the third migration only to the new synthetic database.

After TLS-validated seeding, import mode writes
`inventory-import-synthetic.json` exclusively in the private evidence folder. It
contains one inert synthetic record with distinct display name and exact-payload
SHA-256. Existing files are never overwritten. The handoff records expected counts
one before/two after; it does not report acceptance automatically.

Fourteen guarded native tests and 16 lifecycle tests passed. A generated snapshot
also passed the actual Dart `AssetExport.parse` and real SHA-256 bridge offline.
This proves format compatibility, not native selection/render/confirmation.
A separately approved Windows candidate was built and opened on synthetic HTTPS
fixtures. Operator confirmations cover the successful import and draft-navigation
checks listed above, not unknown-outcome replay, accessibility or process loss.

## Recovery candidate native checks (pending)

Use a newly built, hashed release deployment with the existing explicit import
flag and a fresh native HTTPS fixture. Do not reuse the older import executable.
The current native runner stops services when its app process closes; it does not
support an unreviewed automatic relaunch. Actual separate-process recovery is
covered by the dedicated HTTPS driver, not by this manual session.

1. Sign in to the synthetic fixture and confirm one existing asset. Open Import
   and select `inventory-import-synthetic.json`; preview shows one new asset.
2. Choose Save private recovery JSON and Cancel. Confirm remains unavailable.
3. Save to a new filename. Check the suggested name is
   `asset-desk-import-recovery.json`; acknowledge that it is plaintext private data.
   Do not submit yet. Check that saving alone has not added an asset.
4. Choose private recovery JSON and select the saved file. Confirm outcome unknown
   is shown and no asset has been added. Canceling this picker first must preserve
   the existing review. A restored operation requires a fresh acknowledgement.
5. Acknowledge and Replay same operation exactly once. Refresh inventory: two
   assets, original unchanged, imported record with the expected fixture fields.
6. Record native checks individually. No-repeat-write, keyboard/screen-reader,
   crash durability and controlled native lost-acknowledgement behavior must not
   be inferred from a successful happy-path dialog test.

Build/session execution requires separate approval. Keep Smart App Control and
TLS trust unchanged; stop on a block, do not bypass or rename binaries to evade it.

## Recovery release attempt

The separately approved recovery release build succeeded using the installed SDK
and cache with `--no-pub`. A new isolated HTTPS fixture reached native launch,
but Windows Code Integrity events 3077 and 3033 identified the candidate EXE as
failing the active signing requirements. No recovery dialog or manual UI check
was completed. Build success is not native acceptance.

The runner reported failure at `native-session` and cleanup `stopped`. Synthetic
files and the candidate were retained. No retry, policy change, trust change or
regular backend deployment followed. Keep all recovery native checks pending
until an explicitly approved launch succeeds without weakening machine security.
