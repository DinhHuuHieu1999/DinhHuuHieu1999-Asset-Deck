# Asset detail view

Status: source, HTTPS and listed Windows functional checks verified.
Commit and deployment remain unapproved.

## Scope

Add a read-only View details action to each inventory card. Display name,
category, serial, status, notes, purchase/warranty dates and manual location in
one scrollable view. Keep existing edit actions and list filters unchanged.
No new API route, migration, dependency, production flag or write operation.

## Snapshot honesty

The existing base API has no single-record GET. Use the selected inventory
record as an explicitly labelled list snapshot, including version and timestamps;
never claim it is the latest record. To refresh, return to inventory, refresh the
list and reopen. Do not scan pages or exports to reconstruct a record.

Read dates/location only when their existing flags and source capabilities are
enabled. Accept optional responses only when identity and shared asset version
match the selected record. If either read fails or versions differ, show a clear
error and do not display partially verified supplementary values. Unknown means
an explicitly successful nullable response, not disabled/failed/loading support.
No automatic retry. A session change clears all private details and discards late
responses. Source/record replacement invalidates old requests; Back writes nothing.

## Verification

Capture inventory before editing UI and detail views after at 390/768/1440 pixels
and 200% text. Tests cover optional support off/on, unknown values, literal text,
wrong identity/version, failure, sign-out during reads, source replacement and
Back preserving filters. Synthetic renders/tests are not native accessibility or
real HTTPS acceptance. Runtime fixtures and commits need separate authorization.

## Current evidence

- Final full Flutter suite: 751 passed, one skipped; focused details suite:
  19 passed after adding three inventory-card render cases. Final Flutter analysis
  reports no issues.
- Session invalidation, late-response rejection, source/record replacement,
  explicit unknown dates, wrong identity/version and Back preserving applied
  filters plus unsent search have regression coverage.
- Detail captures at 390/768/1440 pixels with 200% text were visually inspected;
  no clipped horizontal content was observed. Inventory-card captures at the same
  widths were also inspected: View details and Edit asset remain distinct and
  visible. Screen-reader acceptance remains pending.
- One isolated HTTPS fixture completed with the actual Dart client and default
  TLS verification: matching values, foreign-owner refusal, stale snapshot
  rejection, explicit nulls and unchanged base record version. Its owned
  resources stopped. A separate Windows candidate built and opened successfully;
  the operator confirmed initial fields/unknowns, saved dates/location, Back
  preserving search/results and the read-only snapshot label.
- The existing location driver now requires explicit asset-details acceptance;
  older results without that evidence are rejected.
- No commit or deployment has been performed. Codacy is unavailable, not PASS;
  no earlier phase exception is applied to this change.
