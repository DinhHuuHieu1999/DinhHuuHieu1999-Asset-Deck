---
title: "Inventory location implementation plan"
description: "Manual owner-scoped location labels and explicit filtering."
document_type: "plan"
status: "draft"
audience: ["contributors", "operators"]
---

# Inventory location

Approved scope: source and tests for manual location editing and inventory
filtering. No migration execution, fixture, deployment or commit is implied.

## Contract

- A location is a manual label, not GPS, device discovery or filesystem access.
- Nullable label, trimmed edges, 1-120 UTF-16 code units when set. Explicit null
  clears it. Empty labels, malformed Unicode and internal ASCII controls fail.
- Separate authenticated read/update endpoint shares the asset version. A stale
  version never overwrites another edit; unrelated fields and dates stay intact.
- Keep existing clients and JSON v1/v2 schemas unchanged. Existing exports do not
  back up location labels; the client must state this limitation explicitly.
- Opt-in capability defaults off. Missing schema refuses enabled startup; no
  startup migration or destructive rollback is allowed.
- Exact location filtering combines with search/status/category before paging.
  `%` and `_` remain literal. Applying filters resets to page one. Unknown
  location is distinct from no filter.

## Delivery sequence

1. Strict label/update contracts and offline regression tests.
2. Nullable migration source, owner/version-scoped repository and API wiring.
3. Dart transport/model tests; inspect synthetic baseline before UI edits.
4. Location editor and explicit filter UI, preserving drafts/stale results.
5. Separately authorized PostgreSQL/HTTPS/native acceptance and scoped commit.

Rollback disables the optional capability and retains schema and labels.
No new dependency, location permission or background service is required.

## Backend routes and prerequisites

`ASSET_LOCATION_ENABLED=false` is the default. Enabling requires explicit
`backend/migrations/005-asset-location.sql`; startup only checks readiness.
Read/replace uses `GET` / `PUT /api/v1/assets/:id/location`. The separate
`GET /api/v1/assets/locations/inventory` route accepts the existing list filters
plus `locationMode=all|unknown|exact` and an exact `location` label when selected.
Existing list/export/import routes retain their contracts. Source tests alone do not certify runtime behavior; the separate PostgreSQL
and HTTPS acceptance results are summarized below. Native remains pending.

## Source validation checkpoint

Backend contract/repository/controller tests cover literal parameters, owner and
version predicates, unknown labels, paging limits and optional warranty windows.
Dart tests cover session transport, canonical responses, explicit Apply/Refresh,
resetting pagination, stale results, fresh-version editing and draft retention.
Synthetic baseline and candidate layouts were inspected at 390/768/1440 pixels
and 200% text; the narrow helper text now wraps rather than truncates. Capture
fonts omit some icon glyphs; native keyboard/screen-reader checks remain pending.
One approved PostgreSQL fixture applied migrations only to its synthetic database
and passed all four repository scenarios. The owned container was stopped and
retained. A separate approved HTTPS fixture also passed using the real Dart
client and synthetic data. No regular database migration, native build or rollout was run
for locations.

HTTP tests use the real validation pipe and CSRF middleware with a synthetic
auth guard and mocked repository: unauthenticated reads, missing CSRF, invalid
UUID/query/body, literal filters and normalized writes are covered. They do not
certify JWT verification or database ownership enforcement at runtime. A widget
regression also verifies combined location/warranty Apply and Refresh.
