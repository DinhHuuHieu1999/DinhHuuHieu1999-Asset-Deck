# Warranty overview drill-down

Status: source/tests and isolated HTTPS acceptance completed; Windows candidate
built with approval. Native functional checks are confirmed; commit approval remains pending.

Expired and Expiring within 30 days return a typed selection containing the
validated filter and overview UTC reference date. Inventory clears other filters
and requests page one at that date. Pagination and Refresh preserve the selected
reference; explicit Apply starts a fresh reference. Counts and lists are separate
snapshots. Later and Unknown remain informational, not selectable filters.

Back leaves the previous list and drafts untouched. Failed loads retain the last
successful rows and applied-filter identity. Session/source changes invalidate
private overview results and prevent stale navigation.

## Verification

- 53 model/selection contract tests pass.
- 20 overview/navigation tests pass, including both supported filters, date changes,
  pagination, Refresh, explicit Apply resetting the reference, location-aware
  transport routing, failed loads retaining prior identity, session invalidation
  and stale-count selection being disabled.
- Final full regression passed 766 tests with one skipped on the current source;
  analyzer reported no issues.
- Baseline and post-change renders at 390/768/1440 with 200-percent text were
  inspected. The narrow viewport requires vertical scrolling to the second action;
  no horizontal clipping was observed in captured viewports.
- Approved Windows release build completed. The operator confirmed Expired returns
  zero assets for an unknown expiry, then Upcoming returns one asset after saving
  expiry on the reference day. The operator also confirmed Refresh retains the asset, filter and reference,
  and opening overview then Back preserves them without selecting a bucket.
  Dedicated keyboard/screen-reader checks remain pending.

No backend/schema/dependency changes or automatic writes are introduced.

## Isolated HTTPS result

The real Dart client passed one synthetic HTTPS fixture using the existing backend
candidate. Typed selection retained the overview reference across 51 expired rows
in two pages and two upcoming rows; second-owner selected lists remained empty.
Export record comparison before/after confirmed no data changes from these reads.
The owned backend/proxy/container were stopped and synthetic data retained.
This is API/client evidence, not Windows navigation or accessibility acceptance.
