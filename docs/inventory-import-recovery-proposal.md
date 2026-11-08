# Inventory import recovery proposal

Status: approved source/test candidate, not deployed or committed. The earlier
import candidate retained identity in RAM; this candidate adds explicit private
recovery files. The standalone C++ file/hash helper and one isolated recovery HTTPS fixture passed.
The recovery Windows release build succeeded; Code Integrity blocked execution,
so native recovery acceptance remains pending.

## Goal and non-goals

Preserve an exact import request across process loss so the operator can explicitly
replay it without silently creating duplicate assets. Reuse the existing immutable
`AssetImportDraft`, strict JSON/checksum validation and native file-dialog boundary.
Do not add a dependency, backend endpoint, migration, cloud storage or auto-retry.
This is operation recovery, not inventory backup or proof that a write occurred.

## Proposed local contract

Use a distinct versioned format, not an inventory export. Its payload binds:

- The exact configured API base URL, including scheme, host, port and base path.
  Never include credentials, tokens, cookies or secret query parameters.
- The target account ID and original UUID v4 request ID.
- The exact UTF-8 request JSON string and only the five editable asset fields.
- A format version and SHA-256 of the exact payload string.

Validate the complete envelope with duplicate-key rejection, exact field allowlists,
well-formed Unicode, account/key validation and the existing field/count limits.
Request bytes remain at most 1 MiB and records remain 1-500. Bound the outer file
separately at 2 MiB to allow JSON string escaping; reject larger envelopes before
parsing. If a valid request cannot fit the outer bound, refuse recovery preparation
rather than truncate it. A checksum detects corruption, not authenticity.

Reconstruction must retain the exact request JSON and key, not prepare a new
operation from records. The parsed records must agree with that retained request.
Revalidate account and configured API base before showing an actionable review.
Never change configuration, contact a file-supplied endpoint or retarget a file.

## Proposed interaction

1. Prepare and review the immutable draft. Clearly disclose that recovery files
   contain plaintext equipment notes/serials and target identity.
2. Explicitly save a private recovery file before first submission. Cancel or a
   failed save leaves submission unavailable; no write has been attempted.
3. A successful save enables a fresh acknowledgement and explicit confirmation.
   Keep the existing concurrent-write and session-revision guards.
4. After app restart, explicitly choose a recovery file. Validate it completely,
   compare the current endpoint/account, then show a review marked outcome unknown.
   Selecting or reviewing the file must perform no network write.
5. A new acknowledgement permits one explicit replay using the original key and
   request. The current session revision is captured anew; old credentials are
   neither serialized nor restored. Identical replay returns the original receipt;
   changed content under the same key remains a conflict.

An unsent saved operation is also treated conservatively as outcome unknown when
reopened. Do not trust a file-supplied completed/not-sent flag to skip safeguards.
Keep the file after success; never delete, overwrite or silently update it.
Saving the file does not prove later disk durability, confidentiality or safe
synchronization. Losing both process memory and the file still loses recovery.
Do not promise exactly-once behavior after receipt/database loss.

## Required acceptance before rollout

- Offline codec tests: exact round-trip, checksum mismatch, duplicate keys,
  malformed Unicode/shape, forbidden credentials/fields, count and byte bounds.
- Operation tests: original JSON/key retained, account and endpoint mismatch refused,
  no fresh key on restoration, no automatic write, session changes invalidate review.
- UI tests and inspected renders: save-before-submit, Save/Cancel/failure, explicit
  recovered review, new acknowledgement and no silent draft replacement.
- Native file tests: fixed JSON type/name, no overwrite, bounded reads and no content
  in logs. Keep existing export/Inspect behavior unchanged.
- Separately approved synthetic HTTPS test: real commit with lost acknowledgement,
  simulated process reconstruction from the saved file, explicit same-key replay,
  unchanged IDs/count and two-owner isolation. Mocks alone do not prove persistence.
- Separately approved Windows acceptance and source/security coverage review.

## Candidate verification and remaining gates

The approved interaction requires saving before submission; there is no hidden
storage or bypass. Source includes the strict recovery codec, bounded native file
methods, explicit restore/replay UI and current configured endpoint propagation.

- Complete Flutter suite: 220 passed, one opt-in test skipped; analyzer clean.
- Codec tests cover exact identity, endpoint/account binding, malformed data and
  independent request/envelope bounds. Channel tests use mocks, not native dialogs.
- Ten recovery widget tests cover Save cancellation/failure, late save and picker
  completion after session loss/disposal, endpoint rejection, malformed files,
  reconstruction, late checksum completion and explicit same-key replay without
  automatic writes.
  These are injected file/channel tests, not native dialog or OS process tests.
- Before/after synthetic renders were inspected at 390/1440 px with 200% text.
  Narrow screens require scrolling; native glyph/accessibility checks remain open.
- Six Python native source-contract tests passed. The C++ helper compiled with
  the installed MSVC compiler and passed 41 assertions in a new retained synthetic
  directory: SHA-256, separate inventory/recovery bounds, bounded reads and
  no-overwrite writes. The separate Windows release build also compiled the Flutter channel; neither
  result proves native dialogs work.

Still pending: native dialog checks, remaining failure-path review,
security coverage review and Windows native recovery acceptance. The separate
[HTTPS recovery plan](inventory-import-recovery-https-plan.md) records the one
approved live process-reconstruction run; it does not replace native acceptance. Empty Codacy results do not establish analyzer coverage or a
security PASS. Earlier import fixtures do not satisfy these recovery gates.
No build, fixture, regular deployment, upload, deletion or push is part of this
source/test phase.
