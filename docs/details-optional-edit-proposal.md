# Edit dates and location from asset details

Status: source and synthetic Windows functional checks completed. Commit remains
pending separate approval; Codacy is unavailable, not PASS.

## Reuse and boundary

Reuse AssetDatesEditor and AssetLocationEditor. No new endpoint, dependency,
migration, combined form or automatic write is needed. Existing date/location
feature flags and store capabilities continue to control availability.

AssetDetailsSnapshot already verifies optional values against the selected asset
ID and shared version. Pass those verified objects directly to the matching
editor. Do not call the inventory edit wrappers unchanged: they read a fresh
version independently and could silently edit a different version from the one
shown in details. Optimistic concurrency remains enforced by each write.

## Interaction

- Offer Edit purchase / warranty dates and Edit location only for enabled,
  verified values, including explicitly Unknown values. Loading, read errors and
  session invalidation must disable editing, not treat failures as Unknown.
- Reuse the details edit-result lifecycle: one editor at a time, confirmed Save
  closes details and reloads the applied inventory page/filters; Cancel keeps the
  same snapshot. Preserve unapplied filter text and pinned warranty reference.
- Keep existing validation, Keep/Discard, conflict and unknown-outcome protection.
  Never automatically retry or write base fields from either optional editor.
- Sign-out destroys private routes. Late editor/read results must not restore
  details or refresh another account's inventory.

## Verification scope

Capture and inspect the existing details render before modifying UI. Add widget
checks for exact ID/version, capability gating, successful date/location updates,
Cancel/Keep/Discard, 409/unknown outcomes, field isolation and session changes.
Verify applied filters/page and unapplied text survive the intended navigation.
Inspect 390/768/1440-pixel renders at 200% text; run focused tests, full Flutter
suite and analyzer. Codacy availability is separate, not inferred from tests.

Further Windows build/HTTPS fixture runs and commit require separate approval.
This scope does not certify native accessibility, authorize production changes or
include automatic deployment.

## Windows acceptance scope

Use a separately approved synthetic fixture only; never use personal inventory.

1. Open View details, select Edit purchase / warranty dates, save purchase
   `2024-02-29` and warranty expiry `2027-02-28`. Reopen details and verify both
   dates; name, serial, status, notes and location must remain unchanged.
2. From details select Edit location, save `Synthetic room %_1`, then reopen.
   Verify the literal location and both dates remain unchanged.
3. In either editor change a value without saving. Back > Keep editing must
   retain the draft; Back > Discard must leave the saved snapshot unchanged.
4. Apply Search `Synthetic`, open details and Back without editing. The applied
   search and inventory list must remain unchanged.

Record each result separately. A build or successful app launch alone does not
prove these checks. If Windows blocks execution, stop without retrying or changing
Smart App Control, trust or firewall. No commit or deployment is authorized here.

The operator confirmed saved dates, saved location with dates preserved, location
Keep/Discard and Back preserving Search plus one asset. The owned fixture ended
and its resources stopped. Base-field isolation and date-editor draft handling
are widget-tested, not separately operator-confirmed. The full Flutter suite
passed 858 tests with one opt-in skip; analyzer found no issues. Synthetic renders
at 390/768/1440 pixels and 200% text were inspected. These checks do not certify
screen-reader behavior, regular deployment or Codacy/security coverage.
