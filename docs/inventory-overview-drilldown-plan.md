# Inventory overview drill-down proposal

Status: source/tests verified locally; runtime acceptance pending. One isolated HTTPS fixture approved and completed; native candidate built and listed functional checks confirmed; no commit approval.

## Verified gap

Before this change, InventoryOverviewPage rendered status/category counts as plain
Text. AssetsPage opened it with push<void>; selecting a count could not return a
filter selection to inventory.

## Implemented behavior

- Add explicit View assets actions for a status or exact category label.
- Return a typed selection; validate against known statuses/category constraints.
- Replace filters with the selected dimension only, clearing search and other
  dimensions so full-inventory counts do not imply a filtered subset.
- Load page one through existing owner-scoped APIs. State clearly that counts
  and the later list are separate snapshots, not an atomic result.
- Back without selecting preserves applied filters, drafts, results and page.
- Failed navigation loads preserve the old list and its applied-filter identity;
  never relabel old rows with the requested selection.
- Existing edit, detail and overview refresh behavior remain available.

## Boundaries

No backend/API/migration/dependency, writes, notifications or infrastructure.
Capture baseline before UI changes, test typed selection, session invalidation,
literal category labels, cancellation, failed list load, pagination and text 200%.
Fixtures, native build, commit, push and deployment are separate decisions.

## Current verification

Twelve focused overview tests pass, including selection validation, status
navigation, literal category pagination, session invalidation with late response
rejection, failed category load preserving old rows/filter identity and Back
preserving drafts. Updated synthetic renders at 390/768/1440 pixels with 200%
text were inspected. No horizontal clipping was observed in the captured view.

Review found and corrected an existing category boundary mismatch: overview accepts 64 Unicode
code points, while list client/filter checks previously used 64 UTF-16 units. The list, warranty and location-aware client filters, inventory validation and
typed overview selection now count Unicode code points consistently. A transport
regression verifies 64 astral code points reach the request intact and 65 fail
before transport. The focused transport suite also passes all 92 tests, including
direct Unicode boundary checks for warranty and location-aware lists. Existing ASCII limits and literal category matching remain.
Labels with surrounding whitespace are still explicitly unsupported by the
existing trimming filter; they are not silently changed by drill-down.
Full Flutter regression passed: 759 tests, one skipped; analyzer reported no
issues. One isolated HTTPS fixture passed with the actual Dart client: two owners,
all status/category selections, complete pagination matching overview counts,
literal Unicode categories, updated counts and sign-out refusal. Owned resources
were stopped and synthetic data retained. A release Windows candidate was built with installed SDK/cache and --no-pub.
On a separate synthetic HTTPS fixture, the operator confirmed status selection,
category selection clearing status, empty results and Back retaining search/list.
No commit was performed. The listed native functional checks passed; dedicated keyboard/screen-reader
acceptance remains pending. The HTTPS driver alone does not exercise navigation.
