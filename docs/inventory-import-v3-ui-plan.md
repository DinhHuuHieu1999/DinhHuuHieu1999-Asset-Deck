# Import v3 client UI plan

Status: standalone v3 page, operation coordinator and recovery-file adapter
implemented with default-off inventory navigation. Full Flutter offline regression passed. The operator confirmed the scoped
Windows import/recovery interaction checks below; fixture cleanup is confirmed below. PostgreSQL, HTTPS and
response-loss recovery passed separately; these do not prove native UI behavior.

## Reuse and scope

Preserve v1/v2 screens. Reuse the v2 layout, existing v3 draft/receipt/recovery/API
and installed Windows digest/save/choose channel methods. Add a v3 operation
coordinator preserving single-flight, permanent session invalidation and exact
request/key replay. No plugin, dependency, migration or flag-default change.

Before editing UI, capture and inspect the existing v2 rendered page through a
synthetic widget harness: desktop, narrow width and 200% text, including draft,
confirmation and uncertain-result states. Inject session/source/file boundaries;
no backend or credentials. Store captures in a new ignored evidence directory.
Compare matching v3 renders afterward; passing tests alone are not visual proof.

## Compact flow

1. Choose verified export v3; show count, target account, dates and location.
2. Save private recovery JSON; Cancel preserves draft and never submits.
3. Explicit checkbox and Confirm new records; one primary result banner with
   optional technical details, not repeated status paragraphs.
4. Unknown delivery locks replacement and retains exact request/key. Explicit
   replay must be distinct from creating another import.
5. Restore recovery only for the exact endpoint/account. Checksum and saving a
   file never imply successful delivery or authenticity.

## Offline acceptance

- File chooser Cancel preserves draft; malformed selection clears stale preview
  and checksum. No silent v2 fallback or dropped date/location fields.
- Save Cancel/error does not enable confirmation. Keep separate 1 MiB request
  and 2 MiB recovery limits, no-overwrite behavior and visible actionable errors.
- Double submit is blocked; session/source changes reject late receipts and
  permanently invalidate the old review.
- Unknown/recovered operations keep identity; explicit replay reports receipt
  without implying creation of duplicate assets.
- Back Keep/Discard works for unsent drafts; attempted operations retain recovery
  warnings. Keyboard focus and 200% text remain usable.
- Mock native channel names, bytes, size limits, invalid results and cancellation;
  these tests are not native file-dialog acceptance.

## Execution boundary

Next approval covers source, synthetic baseline renders, tests and analyzer only.
Live fixtures, Windows build/open, commit, push and deploy remain separate.
No real inventory, automatic retry or Windows security-policy changes.

## Current offline evidence

The synthetic v2 baseline was captured before UI edits. V3 draft/confirmation
renders were captured at widths 390, 768 and 1440 with 200% text; narrow and desktop
captures were inspected. Dates and location are visible; operation identity and
endpoint are collapsed under Operation details. The capture font lacks some
Unicode/icon glyphs, so these screenshots do not establish glyph correctness.

Twenty page/channel tests passed, covering explicit confirmation, unknown-outcome
replay, recovery reconstruction, cancellation, session/context invalidation,
departure guards and mocked native errors. Flutter analyzer reported no issues.
The first mock-channel run exposed a test fixture missing the required location;
that fixture was corrected. Capture now waits for paint after scrolling.

Navigation requires import v3, import, dates and location flags plus a signed-in
v3-capable source, independently of import-v2/export-v3. Added missing-location,
v2-file and malformed-file rejection tests and operation single-flight/late-reply
regressions. Uncertain and replay states were captured at all three widths; the
narrow uncertain-state capture was inspected. The result now uses one highlighted
live-region banner. A new capture test initially assumed an offscreen lazy-list
button existed; scrolling until built fixed that harness failure.

Native acceptance, disabled-route runtime acceptance, Codacy, commit and deployment
remain separate. Capture font limitations remain unchanged.

## Final source checkpoint

Full `flutter test --no-pub` completed with 713 passing tests and one skipped
Python-executable opt-in check. `flutter analyze --no-pub` reported no issues.
The complete run includes legacy v1/v2 and existing inventory regression tests.
Two earlier full runs failed only in the new narrow render harness: lazy children
were not built or the large tile center was offscreen under the default test
font. The harness now scrolls to built children and taps the actual checkbox;
the final full run passed without requiring a capture-font environment variable.
No skipped check is counted as a pass. No native/disabled-route/Codacy result is
inferred from these offline checks.

## Native runner source checkpoint

The existing native runner now accepts the exclusive `--import-v3-mode` profile.
It requires an exact hashed release manifest with the import, import-v3, dates
and location defines, and rejects additional v2/export flags. The fixed synthetic
import file contains one asset with both dates and location. Handoff expectations
remain one existing asset, two after confirmation, and still two after explicit
same-key recovery replay. Existing v1/v2/location/export profiles are preserved.

The native runner never builds or relaunches an app. Its original 1-30 minute
limit, loopback/TLS prerequisite checks, ownership cleanup and retained evidence
remain unchanged. Twenty-eight guarded native-runner tests and 196 guarded HTTPS
lifecycle tests passed. No Docker, TLS, backend or native process was executed by
these tests; session completion alone never marks manual acceptance successful.

At this source-only checkpoint, the proposed next live step required a
separately approved Windows candidate build using the
installed SDK/cache with `--no-pub`, then one new synthetic HTTPS session up to
30 minutes. Check allowed/free ports before build and bind the manifest to that
endpoint. Do not download, change SAC/trust/firewall, retry a blocked launch or
use real accounts/data. Planned manual steps: review dates/location, Save recovery,
confirm once, Refresh to two assets, restore the same recovery and replay,
Refresh still two. Also check chooser Cancel and visible result feedback.

## Observed Windows interaction acceptance

One approved release build completed with the installed SDK/cache and `--no-pub`.
The exact hashed candidate used a separately approved loopback HTTPS fixture
`725a642b5a00670e28d5811ea46cf893`. The operator confirmed preview dates/location,
save recovery followed by explicit import and refresh to two assets, then restore
and explicit same-key replay still showing two assets. The operator also confirmed
unchanged dates/location and chooser Cancel retaining the prior preview.

These are operator-reported interaction results, recorded separately from runner
completion. They do not establish screen-reader coverage, every error state,
disabled-route runtime behavior, production deployment or Codacy acceptance.
No commit or deployment has been performed. Fixture cleanup must be confirmed
from its terminal result and resource ownership; it is not inferred from these
manual reports. Private recovery files and credentials remain local ignored data.

### Fixture cleanup

The runner ended with `sessionEnd=app-closed`, `stage=completed` and
`cleanup=stopped`. Independent Docker inspection confirmed the exact fixture label,
stopped container, retained matching volume and loopback-only database binding.
The runner deliberately leaves `nativeAcceptance=pending`; the separate operator
record supplies only the scoped interaction confirmations listed above. No blanket
native/accessibility acceptance is claimed.
