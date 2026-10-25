# Asset Desk Windows native acceptance

## Current boundary

Windows runner source is rendered from the installed Flutter 3.47.4 SDK template.
Plugin registrant/CMake metadata was generated offline with the lockfile enforced
after the first build exposed its absence. The release build then passed, and
the exact isolated candidate process opened on a synthetic HTTPS fixture.
The operator confirmed the functional checks listed below on fixture
`8d19c532000c26d91366ef9ab9356903`. Native accessibility and error/conflict
interaction checks remain pending.

The source selection, substitutions and hashes are recorded in
`windows-runner-provenance.json`; the runner retains the Flutter license.
The stock Flutter icon is a template asset, not an Asset Desk brand identity.
No platform build, executable launch or native acceptance is implied by source
tests. Do not disable Smart App Control or bypass certificate validation.

## Separately approved execution

1. Build a release candidate with an explicit fixture-only HTTPS endpoint ending
   in `/api/v1`. Use installed SDK/cache and no automatic dependency download.
   Stop on missing tools, cache or an Application Control denial; do not retry
   or weaken protection automatically.
2. Copy the complete release deployment to a new directory under
   `.local/windows-candidates/`. Keep the original artifact. Record its exact
   build command, source revision/diff and compile-time endpoint in local evidence.
3. Place `candidate.json` beside `asset_desk.exe`. Schema version 1 requires
   `buildMode: "release"`, the exact `endpoint`, and a `files` object mapping
   every deployment-relative POSIX filename to its SHA-256. Exclude the manifest
   itself. The EXE, `flutter_windows.dll` and `data/icudtl.dat` are mandatory.
   Hashes detect drift; a manifest alone does not prove which endpoint was compiled.
4. Run the native fixture once only after separate approval. Its explicit flags
   are `--execute-native --execute-synthetic --candidate`, an existing immutable
   image ID, existing localhost certificate/key, direct SDK `dart.exe`, three
   distinct loopback ports and `--minutes` (1–30). No implicit build, pull, retry,
   trust/firewall change or regular backend is permitted.

The native harness reuses the existing owned database/backend/TLS lifecycle.
Before opening the candidate, a Dart seed client validates default TLS and an
exact random marker, then creates one synthetic account and equipment record.
Credentials appear only in the ignored fixture `operator-handoff.json`, not in
console output. Do not post that file or use a real account/equipment data.
The proxy permits only the existing synthetic API routes, not arbitrary upstreams.

The session ends on app closure or at its deadline. A failed owned service or
nonzero app exit fails the scenario. Cleanup stops exact child handles and the
label-verified container, retaining its volume and evidence. Never delete these
automatically. Reaching the deadline is not manual acceptance: the result remains
`nativeAcceptance: "pending"` until the operator confirms the checks below.

## Manual checks

- Sign in using only the fixture account; find `Synthetic native asset`.
- Search `%_` and filter `stored`; clear filters and refresh.
- Add a synthetic asset, edit its fields/status, save and refresh; verify values.
- Edit without saving: keep the draft, then discard it; verify stored data did
  not change. Check keyboard focus, labels and text scaling on the actual window.
- Sign out and sign back in with the same fixture account; verify saved records.
- Confirm stale/error messages do not imply a successful save or auto-retry.

A later restart/restore check needs a separate execution plan; this bounded UI
session does not certify deployment, recovery, screen-reader support or production
readiness. If SAC blocks the EXE, retain native acceptance as pending.

## Operator-confirmed functional results

The operator confirmed finding the seeded asset, literal `%_` search with
`stored` status, clearing filters, adding `Synthetic test laptop`, changing its
status to `in_use`, save/refresh persistence, keeping/discarding an unsaved Notes
draft, and signing out/in with the same synthetic account without losing data.
The operator also confirmed Tab/Shift+Tab navigation, visible focus and Enter/Space
activation. These confirmations do not cover native text scaling,
screen readers, stale/conflict errors, restart/restore or regular deployment.
The harness lifecycle result is separate from these manual confirmations.

## Offline contracts

```powershell
python -B scripts/test_windows_runner.py -v
python -B scripts/test_client_https_fixture.py -v
python -B scripts/test_native_https_fixture.py -v
```

These tests inspect source and use mocked runtime/socket boundaries. They do not
read a real TLS key, launch the candidate, build, or start Docker/backend services.
The Flutter tests additionally check bounded marker validation using fake streams.
