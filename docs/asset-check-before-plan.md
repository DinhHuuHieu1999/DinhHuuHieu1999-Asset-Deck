# Checked-before inventory filter

Status: source, isolated PostgreSQL/HTTPS and operator Windows checks passed.
Not committed or deployed. Codacy coverage remains unavailable, not PASS.

## Contract

`checkMode=before` requires `checkBefore=YYYY-MM-DD`. It matches strictly earlier
manual check dates, excluding the boundary day and Unknown (SQL NULL). Calendar
years 0001 through 9999 are accepted; no timestamps, trimming or coercion.
All/unchecked remain compatible and reject a non-empty stray cutoff.

The existing check-date feature flag controls this filter. No migration or new
dependency is needed. Fixed SQL binds the cutoff before pagination on base,
warranty, location and combined lists, independently of the warranty reference
day. Legacy requests do not reference the optional column or add unused values.

Apply validates the draft; Refresh and pagination retain the applied cutoff.
Reset clears the cutoff and validation error. Failed Apply preserves the old
page and applied scope. Matching selection export is unavailable while either
check-date filter is applied: its schema cannot represent that scope. Existing
full exports/imports are unchanged. No reminders or schedules are introduced.

## Verification

- Full offline regression at the initial candidate: 748 backend tests with 85
  opt-in skips; 938 Flutter tests with one skip; typecheck and analyzer passed.
- Subsequent focused checks: 121 client/argument tests, 10 UI filter tests,
  13 PostgreSQL lifecycle tests and eight HTTPS lifecycle tests passed.
- Synthetic UI inspected at widths 390/768/1440 with 200% text; no overflow.
- One approved PostgreSQL fixture passed six scenarios without skips, covering
  strict boundaries, Unknown exclusion, owner isolation, pagination and combined
  location/warranty scope. Ownership-checked cleanup stopped the container.
- HTTPS acceptance passed on the third separately approved fixture. The first
  two failures exposed driver scope arguments, not a server defect: exact
  location was supplied while location capability was disabled. The client
  correctly refused it before HTTP. A regression guards that refusal. The fixed
  driver passed base/warranty/location/combined boundaries and two-owner checks.
  All three fixtures stopped; failed evidence remains retained. No automatic
  retries were made.
- The operator confirmed Windows date save/Refresh, same-day cutoff returning
  zero, next-day cutoff returning one, Refresh using the applied rather than
  draft cutoff, empty cutoff preserving the old result with an error, Reset
  clearing that error, and Details/Back preserving the applied filter and list.
  The native runner recorded app-closed and stopped cleanup. Its automatic
  `nativeAcceptance: pending` marker does not encode these manual confirmations.

These checks use isolated synthetic data, not a regular deployment. Containers,
volumes and local evidence are retained. Broader native accessibility and
security certification are not claimed. Any commit requires separately reviewed
scope and approval; prior coverage exceptions do not apply to this change.
