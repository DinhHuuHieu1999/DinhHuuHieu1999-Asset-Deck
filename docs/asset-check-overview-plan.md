# Manual check-date overview

Status: source implemented; offline verification recorded below. Runtime acceptance pending.

## Scope

Show complete counts for the authenticated owner's inventory, independent of
current list filters and pagination. The operator chooses a strict calendar
cutoff, using the same rules as Checked before. This is a manual assertion, not
proof that equipment was inspected.

One aggregate statement returns `complete`, `cutoff`, `total`, `unknown`,
`before` and `onOrAfter`. Buckets partition the owner inventory: NULL, date
strictly before cutoff, and date greater than or equal to cutoff. Validate safe
nonnegative integer counts and require their sum to equal total. Never infer
counts from a fetched page or return a partial overview.

## Integration

- Add an authenticated, no-store read endpoint under the existing optional
  check-date module. Bind owner and cutoff; reject extra or malformed query
  parameters before querying. Keep the existing default-off feature flag.
- Reuse Unknown and Checked before list filters for drill-down. Add a bounded
  on-or-after mode across base/location/warranty/combined repositories and Dart
  transport so the third bucket also opens its exact list, not All assets.
- Drill-down replaces incompatible list filters, starts at page one and retains
  the applied sort. Back without selection preserves the prior inventory state.
- Use a separate optional Dart capability and strict response validation. Keep
  the previous successful overview visible on load failure, clearly labelled
  as the last result; never present a failed draft cutoff as applied.
- Capture and inspect a synthetic baseline before UI changes, then inspect
  narrow and wide layouts at 200% text. Provide readable errors and keyboard
  actions using existing overview patterns.

No migration, production dependency, schedule, notification or automatic write.
Exports/imports remain unchanged; matching selection export stays unavailable
for check-date filtered lists whose scope its schema cannot represent.

## Acceptance

Source tests cover empty inventory, partition totals, boundary equality, NULL,
malformed cutoff/counts, owner binding, route auth, feature-off behavior and all
list route combinations. Client/UI tests cover cutoff validation, applied vs
draft state, refresh, failed requests, drill-down and Back preservation.

Real PostgreSQL/HTTPS and Windows checks require separate isolated execution
approval. Offline tests do not establish their acceptance. No fixture, build,
commit, push or deployment is authorized by this design document. Codacy
coverage must be reported independently; prior exceptions do not transfer.

## Offline verification

- Full Flutter suite: 968 passed, one opt-in test skipped. The subsequent
  session-invalidation regression brings the focused overview suite to ten
  passing tests. These reject a late response after sign-out, preserve applied
  search/sort and an unsent draft on Back, and disable stale bucket actions
  after a failed refresh.
- Full backend rerun after the DTO expectation repair: 780 passed and 87
  opt-in tests skipped. Backend typecheck passed. The new four-scenario
  PostgreSQL suite separately typechecks and skips without explicit opt-in.
- All 87 mocked PostgreSQL lifecycle tests passed, including five new overview
  harness tests. See [fixture plan](asset-check-overview-fixture-plan.md).
- Flutter analyzer passed after the additional session regression.
- Synthetic overview layouts were inspected at 200% text on narrow and wide
  viewports. This is not Windows native acceptance.

The approved isolated PostgreSQL fixture passed all four scenarios with no
skips; its owned container was stopped and volume retained. See the fixture
plan for evidence. The separately approved rebuilt HTTPS fixture also passed with the real
Dart client after route/proxy integration repairs. Native build, commit and
deployment have not been performed for this phase. Codacy coverage remains unverified.

## Windows acceptance checklist (pending)

Use the existing native runner's exclusive `--check-mode` with its exact
check/date/location build defines. Build from a short source path using the
installed SDK/cache and `--no-pub`. The candidate endpoint must match the
new loopback TLS fixture. Keep the session bounded to 30 minutes; stop if
Windows blocks execution, without changing SAC or automatically retrying.
No import/export capability, regular backend change or deployment is needed.

Use only the newly generated synthetic handoff account and seeded asset:

1. Open Check-date overview, enter cutoff `2024-03-01`, Apply. Expect total 1,
   Unknown 1, Before 0 and On or after 0. View Unknown opens exactly one asset.
2. Reset filters; edit the seeded asset's check date to `2024-03-01`, save and
   refresh. Overview cutoff `2024-03-02` must show Before 1. View Before opens
   exactly one asset and pins that cutoff through Refresh.
3. Overview cutoff `2024-03-01` must show On or after 1 and Before 0. Enter
   draft `2025-01-01` without Apply; View On or after must still use the applied
   `2024-03-01`. Refresh keeps that inclusive filter.
4. Apply Search `Synthetic` and Name A-Z. Open overview then Back without
   selecting a bucket. Applied search, sort and the one-record list remain.
5. In overview, Apply invalid `2023-02-29`. Expect a readable error, clearly
   labelled old counts and disabled bucket actions, not a new applied cutoff.

Close the app when finished. A successful lifecycle result is not a substitute
for these operator confirmations. Native keyboard/text-scale/screen-reader
coverage must remain separately stated; prior-phase confirmations do not
certify the new controls.

## Cutoff input behavior

Opening the overview initializes the draft from the device local calendar date.
Apply validates and uses the draft; Refresh reloads the last applied cutoff
without replacing the draft. Format errors and nonexistent calendar dates have
separate messages. Reopening the page initializes a new draft.
