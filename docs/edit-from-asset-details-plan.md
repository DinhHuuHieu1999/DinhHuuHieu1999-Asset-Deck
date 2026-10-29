# Edit from asset details

Status: source/tests and separately approved Windows fixture checks passed; no
commit or deployment approval.

## Flow

Keep details explicitly labelled as an inventory snapshot. Offer Edit asset only
when a caller supplies the existing editor capability and optional details reads
have completed successfully. Pass the selected record unchanged, including its ID
and optimistic version; never reconstruct a record from labels or scan inventory.

Reuse AssetEditor validation, draft Keep/Discard and conflict/unknown-outcome
handling. Cancel returns to the same details snapshot without reloading inventory.
A successful save closes details and refreshes inventory using its applied filters;
do not leave an obsolete details snapshot presented as the saved record. Preserve
unapplied filter text. Session changes invalidate private routes and late results.
Editing base fields must not rewrite dates or location.

## Verification boundaries

Capture current details before UI edits. Cover correct record/version, success,
cancel, draft preservation, conflict, unknown outcome, disabled/loading/error
states, sign-out and Back preserving filters. Review synthetic renders at
390/768/1440 pixels and 200% text. Native and HTTPS execution require separate
approval; no migration, dependency, automatic retry or deployment is included.

## Source verification

The source slice passes 840 Flutter tests with one opt-in test skipped and clean
Flutter analysis. Eleven focused tests cover the selected ID/version, Save/Cancel,
page-two and applied-sort preservation, 409/503 draft protection, unverified
optional information, session invalidation (including a late write after root
sign-out) and large-text layout. Synthetic
390/768/1440-pixel renders at 200% text were inspected; they are not native or
screen-reader acceptance. No new database, backend, dependency or migration is
needed. Codacy tools are unavailable in the active client, not PASS. The Windows
release build and listed synthetic native functional checks passed;
commit approval remains pending.

## Native functional checks

The operator confirmed these checks on the separately approved synthetic Windows
candidate:

1. Open View details, then Edit asset. Change Notes to Details edit test and Save.
   Reopen details: saved Notes appear; purchase date, warranty and location remain
   unchanged.
2. Open Edit again, change Notes, Back then Keep editing; the draft must remain.
   Back then Discard must return to the unchanged saved snapshot.
3. Apply Search Synthetic, open View details and Back without editing. Search
   remains Synthetic and the inventory still contains one asset. Unapplied text,
   sort and page preservation are covered by widget tests, not this manual check.

Only the fixture account and synthetic record were used. These listed functional
steps are accepted from operator observation, not inferred from widget tests. Do not change Windows security policy.
