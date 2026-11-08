# Inventory location overview

Status: source/tests and one PostgreSQL fixture completed. HTTPS harness
source/offline checks and one HTTPS execution completed. Listed Windows
functional checks were operator-confirmed; commit and deployment pending.

## Contract

Provide an authenticated, no-store GET `assets/locations/overview` under the
existing opt-in location capability. Reject query parameters: counts cover the
entire authenticated owner inventory, independent of list filters and pages.
Return `complete: true`, `total`, `unknown`, and `locations` containing exact
case-sensitive normalized labels and positive counts. Unknown means SQL NULL;
never merge it with a blank label. Preserve literal percent/underscore labels.
Use one grouped SQL statement for a consistent statement snapshot. Bound output
to 1,000 known labels; refuse with 422 rather than silently truncate. Validate
safe integer counts and sum consistency. No migration or new dependency.

## Client and UI

Use a strict Dart response decoder and optional source capability. Show a
separate overview with total, unknown and known-location counts; tapping a label
opens inventory using exact mode, tapping unknown uses unknown mode. Do not
silently carry unrelated draft filters into these selections. Preserve previous
counts as explicitly stale on failure; reject late results after session changes.
Capture and inspect the current rendered inventory before UI implementation.

## Verification and boundaries

Offline tests cover zero inventory, null/known groups, literal labels, malformed
counts, overflow, bounds, owner isolation SQL predicates, auth/query rejection,
client session changes and UI filter navigation/error states. PostgreSQL/HTTPS
and Windows manual acceptance need separate approval; offline tests cannot
certify live SQL behavior. No auto refresh loop, mutation, geolocation or new
infrastructure. Rollback hides the new entry; data/schema remain unchanged.

## Operator-confirmed Windows functionality

On the bounded synthetic fixture, the operator confirmed total/unknown 1/1,
assigning `Synthetic room %_1` and counts 1/0 with one known asset, selecting the
label to open Exact mode, clearing location back to Unknown 1, and Back without
selection preserving inventory filters/list. Asset name/status remained unchanged.
These are operator confirmations, not automated UI observation. They do not cover
screen readers, native scaling, error/late-session interaction or deployment.
