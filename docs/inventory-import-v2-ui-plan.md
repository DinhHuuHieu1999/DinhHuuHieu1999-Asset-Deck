# Inventory import v2 UI slice

Status: UI source and offline tests authorized; native execution remains pending.
Backend/client HTTPS and recovery evidence is recorded in the
[integration plan](inventory-import-v2-https-plan.md).

## Boundary

Keep the existing v1 page and operation state contracts unchanged. Add a separate
v2 entry and review flow using the existing v2 draft/recovery/source interfaces.
Require an explicit client v2 flag (default false), existing import/date flags,
authenticated session and actual v2 source capability. Never route v2 through v1
or silently drop dates. Reuse native file abstractions only where their byte and
no-overwrite contracts fully satisfy v2; no new dependency is planned.

## Before editing UI

Capture and inspect the existing v1 page using its synthetic widget harness. No
real account, backend or native app is required. Record baseline and candidate
renders at widths 390/768/1440 and 200% text, with local ignored PNG output.

## Required behavior

- Show target account, count, all editable fields and both explicit nullable dates.
- Require private recovery save, fresh acknowledgement and explicit confirmation.
- Cancel/save failure never submits; prevent duplicate confirmation.
- Session/account/source/file changes invalidate prepared review and late results.
- Reopening recovery selects no endpoint and performs no automatic write/retry.
- Uncertain outcome retains exact request bytes/key for explicit same-key replay.
- Preserve Keep/Discard behavior, keyboard focus and readable long-content layout.
- Keep v1 navigation, codecs and recovery compatibility tests unchanged.

## Acceptance and limits

Run scoped unit/widget tests, analyzer, synthetic visual inspection and full client
regression before proposing execution. Actual Windows dialogs/recovery remain a
separate gate; keep Smart App Control/trust intact. No backend rollout, migration,
import of real files, commit or push is implied by source approval.

## Offline implementation evidence

The separate v2 page and typed recovery adapter preserve v1. Navigation requires
`ASSET_DESK_ENABLE_IMPORT_V2`, the existing import/date flags, a signed-in session
and v2 source capability. The new flag defaults to false.

Synthetic baseline and candidate PNGs were inspected, including the narrow
390-pixel layout at 200% text. Long content scrolls; native dialogs and keyboard
behavior are not certified by these captures. Local evidence remains under
`.local/import-v2-ui-baseline-20261027` and
`.local/import-v2-ui-candidate-20261027`.

Full Flutter analysis reported no issues; regression reached 509 passing tests
and one opt-in skip before the additional Cancel/save-cancellation regression.
Navigation checks cover flag prerequisites and missing v2 capability. Codacy
returned empty findings for the navigation files; this is not security or analyzer
coverage certification. Recovery/native acceptance and additional async-context
review remain pending before proposing Windows execution.

The subsequent focused run passed 18 UI/navigation tests, including reopening a
v2 recovery without automatic submission and explicit replay of the exact saved
request/key. A regression first reproduced a late digest error replacing the
session-invalidation message; the v2 error handler now checks context generation
before changing that message. Cancel retains the draft and cancelling its first
recovery save leaves confirmation disabled. These are offline widget contracts,
not Windows file-dialog acceptance.

Six v2 recovery-channel tests also passed (19 tests together with page tests):
bounded byte-only selection, cancellation, exact saved JSON, separate checksum
method and size limit, native failures and missing-plugin refusal. The narrow
390-pixel lower-page capture was inspected at 200% text: both dates, private-file
warning, acknowledgement and disabled confirmation are visible without overflow.
The capture font lacks some CJK/emoji glyphs; this does not certify font coverage.

The final focused page/navigation/recovery run passed 26 tests and analyzer was
clean. Explicit regressions reject a v1 export on the v2 page without fallback
and hide the v2 entry while signed out. The full-client regression log records
518 passing tests and one opt-in skip; the focused run was repeated after the
last test edits. Logs and PNGs are local evidence, not committed artifacts.

## Native preparation checkpoint

The native runner has a separate `--import-v2-mode` profile. It requires exact
import/v2/date build defines, uses the existing v2 backend profile and writes a
checksummed synthetic v2 file with both dates. Legacy native import defaults are
unchanged. Mocked runner tests do not prove a real application session.

One approved short-path Windows release build passed with `--no-pub`. It was not
launched: its selected endpoint used port 28443, which the existing fixture guard
excludes. The guard was preserved; no fixture database/container was created.
A new candidate for a non-default isolated port requires separate approval.
This packaging mistake is not evidence of Smart App Control blocking the build.

The separately approved corrected build for `https://localhost:29443/api/v1`
passed after all three loopback ports were checked free. Its single native
fixture attempt terminated abnormally with launcher exit code 1073807364 and no
completion report or operator handoff. The exact labeled PostgreSQL container
was later observed exited (255); all three loopback ports were closed. Its volume
and candidate were retained. PostgreSQL logs showed readiness, but do not explain
the launcher termination. Native acceptance remains pending; no retry or security
policy change was performed, and SAC is not established as the cause.

The shared runner now flushes and fsyncs a local `progress.jsonl` before each
major step. Each row contains only a validated fixture ID and fixed stage name;
commands, arguments, credentials, API payloads and exception details are excluded.
These checkpoints identify the last attempted stage, not successful completion.
Logging failure refuses further scenario work while still entering owned cleanup.
This source-only diagnostic addition does not authorize another fixture run.

## Operator functional acceptance checkpoint

On the isolated synthetic Windows candidate, the operator confirmed two assets
after import and the imported dates `2024-02-29` / `2027-02-28`. In a subsequent
authorized session, the operator confirmed saving and reopening the private
recovery file, explicitly replaying the same operation and retaining exactly two
assets. These confirmations cover the instructed functional flow, not screen-reader
behavior, security certification or a regular deployment. Earlier interrupted and
expired sessions remain historical evidence, not successful acceptance.
