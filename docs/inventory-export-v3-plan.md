---
title: "Inventory export v3"
description: "Location-aware export without changing existing schemas."
document_type: "plan"
status: "draft"
audience: ["contributors", "operators"]
---

# Inventory export v3

Preserve export v1/v2 and import v1/v2. The separate owner-scoped export v3
contains public asset fields, purchase/warranty dates and nullable manual
location. No GPS, discovery, import v3 or automatic execution is included.

## Contract and implementation

- Keep the `asset-desk-inventory` envelope with schemaVersion 3, exact UTF-8
  payload and SHA-256. A checksum is not proof of authenticity.
- Export all owner records in one statement snapshot, not a filtered UI page.
- Enforce 500 records and a 1 MiB envelope; reject incomplete output.
- Project only public fields and reject invalid/noncanonical stored locations.
- Authenticate `GET /api/v1/assets/export/v3`, reject query parameters and send
  `Cache-Control: no-store`.
- Backend `ASSET_EXPORT_V3_ENABLED` defaults false and requires dates/location.
  Flutter `ASSET_DESK_ENABLE_EXPORT_V3` defaults false; navigation also requires
  dates/location and the export capability.
- Explicit Prepare/Save and read-only Inspect use the existing bounded native
  channel. No import v3 or silent fallback to older schemas is added.

## Verification evidence

Recorded full offline runs passed backend typecheck and 502 backend tests
(50 opt-in skips), Flutter analyzer and 644 Flutter tests (one skip).
Later native-profile checks passed 159 HTTPS orchestration tests and five
Dart seed tests. Native adapter tests are mocked, not native acceptance.

Synthetic export/Inspect renders were inspected at widths 390, 768 and 1440
with text scale 200%. Some Unicode glyphs were unavailable in the capture font;
these renders do not establish native accessibility or font coverage.

The isolated [PostgreSQL fixture](inventory-export-v3-fixture-plan.md) passed
four scenarios with zero skips: extreme/nullable dates and literal location;
51 owner records with second-owner exclusion and unchanged rows; refusal above
500 records; consistent snapshot during an observed concurrent committed edit.
Its owned resources stopped and its volume/evidence were retained.

The separate [HTTPS acceptance](inventory-export-v3-https-plan.md) passed with
the real Dart client, including auth, query refusal, no-store, owner isolation,
checksum and unchanged v1/v2 schemas. Its resources also stopped with evidence
retained. Neither fixture changes the regular backend or database.

## Native profile and operator confirmation

The opt-in `scripts/native-https-fixture.py --export-v3-mode` requires an exact
candidate manifest with these feature defines all `true`, and no extra defines:
`ASSET_DESK_ENABLE_EXPORT_V3`, `ASSET_DESK_ENABLE_ASSET_DATES`, and
`ASSET_DESK_ENABLE_ASSET_LOCATION`. Mixed profiles are refused.

The separate `flutter/tool/native_export_v3_seed.dart` validates the random TLS
marker before creating a synthetic account and one asset with dates
`2024-02-29` / `2027-02-28` and location `Synthetic room %_1`. Credentials stay
in the ignored private handoff. Existing profiles keep their original seed.

The approved Windows release build passed using existing SDK/cache and
`--no-pub`. The complete deployment was copied and hashed in a new ignored
candidate directory; prior artifacts were retained. On that candidate the
operator confirmed:

1. Save then Inspect showed a matching checksum, the expected dates/location.
2. Cancelling file selection retained the validated preview.
3. Invalid synthetic JSON was refused and cleared the previous preview and
   checksum-success message.

These are functional confirmations, not full accessibility, security, recovery
or production-deployment certification. A session is capped at 30 minutes and
ends on app closure or its deadline; cleanup is a separate lifecycle result.
Keep SAC, TLS trust and firewall unchanged. Stop without retry if Windows blocks.
No launch or successful build alone counts as manual acceptance.

## Remaining review boundaries

Codacy is unavailable for the latest edits, not PASS. Review must retain this
limitation and distinguish earlier scan coverage from the current source.
No v3 source has been staged or committed, and no deployment or push is implied.
The native session ended on app closure with `cleanup: stopped`; an independent
Docker inspection confirmed the exact labeled container was not running. Its
container, volume and evidence were retained.
