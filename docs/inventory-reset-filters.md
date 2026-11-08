# Reset inventory filters

Status: source/tests, synthetic renders and four operator-confirmed Windows
functional checks completed. Commit and deployment remain separately gated.

Reset filters requests page one with blank search/category/status/warranty and
All locations, retaining the last successfully applied sort. An unapplied sort
choice is discarded on successful reset. No backend change, migration, dependency
or asset write is involved.

The request bypasses invalid filter drafts. Only a successful response clears the
controls, location validation error and warranty reference, and replaces the
applied scope and list. A failed reset retains the previous applied scope, page,
results and draft controls with the normal stale-data error. Refresh still uses
the last successfully applied scope; it follows existing warranty-reference
refresh behavior. Loading disables Reset and Apply; no automatic retry occurs.

## Verification boundary

Widget checks cover combined filters, page two, applied versus draft sort,
failed-reset preservation, invalid Exact location recovery, disabled optional
capabilities, warranty-only routing and late responses after disposal. Synthetic
renders at 390/768/1440 pixels and 200% text are inspected before/after changes.
These checks do not certify native keyboard/screen-reader behavior or deployment.
Codacy availability is reported separately, never inferred from passing tests.

## Windows functional checks

The operator confirmed the following on a separately approved synthetic Windows
fixture; owned resources stopped after the app closed:

1. Apply Search `Synthetic`, status `repair` and Name A-Z. Expect zero matches.
2. Select Recent updates without Apply, then Reset filters. Expect all synthetic
   assets on page one, blank search, All statuses and applied Name A-Z.
3. Refresh inventory. Expect the cleared applied filters and Name A-Z to persist.
4. Select Exact location with blank input, Apply to show validation, then Reset.
   Expect All locations, no location validation error and the unfiltered list.

A fixture/build/commit requires separate approval; do not change Windows security
or retry a blocked native executable automatically.

The full Flutter suite passed 867 tests with one opt-in skip; analyzer found no
issues. Failure preservation, reset from page two and late responses remain
widget-tested only, not manual Windows claims. Native keyboard/screen-reader
acceptance remains pending. Codacy is unavailable, not PASS; a coverage exception
requires explicit approval for the exact reviewed file hashes.
