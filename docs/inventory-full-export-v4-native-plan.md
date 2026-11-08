# Full export v4 Windows acceptance

## Approval boundary

A separately approved Windows release build and isolated native session ran.
No additional session or rollout is implied.
Use the existing SDK/cache with `--no-pub`, a new isolated candidate directory,
and the existing owned synthetic HTTPS lifecycle. Do not change SAC, trust,
firewall, dependencies or the regular backend. Stop if Windows blocks execution;
do not retry or automatically relaunch. Closing the app ends the fixture.

## Exact candidate contract

The candidate manifest must pin the fixture endpoint, release mode and every
file hash. The dedicated `--export-v4-mode` profile requires exactly these flags:

- ASSET_DESK_ENABLE_EXPORT_V4=true
- ASSET_DESK_ENABLE_ASSET_CHECK=true
- ASSET_DESK_ENABLE_ASSET_LOCATION=true
- ASSET_DESK_ENABLE_ASSET_DATES=true

The v4 profile is exclusive of import, selection and older fixture modes.
Native seed creates one synthetic asset with purchase 2024-02-29, warranty
2027-02-28, location Synthetic room %_1 and last checked 2024-03-01.
Credentials remain in the ignored local handoff, never in chat or committed docs.

## Operator checks

1. Export JSON v4 with manual check dates: Prepare, verify one asset and save to
   a new private filename. Cancel Save must preserve the prepared snapshot.
2. Inspect JSON v4: select the saved file. Verify Checksum matches, one asset,
   both purchase/warranty dates, exact location and last checked 2024-03-01.
3. Choose file then Cancel: preview and Checksum matches must remain.
4. Choose invalid JSON: old preview and Checksum matches must both disappear.

Use no real account, file or equipment data. No import is involved. Leave native
acceptance pending until the operator confirms; a successful launch is not enough.
Limit the session to 30 minutes, verify ownership before cleanup and retain data.

## Offline verification

36 native lifecycle tests, 255 shared HTTPS tests and six scoped Dart tests pass;
Flutter analyzer reports no issues. These are source checks, not native acceptance.

## Observed native results

The operator confirmed saving one asset, inspecting its checksum and all four
optional fields, retaining preview/checksum on picker Cancel, and clearing both
on invalid input. Independent Python verification matched the saved checksum,
count and field values. A separately approved reopened session confirmed that
Save-dialog Cancel retains the prepared snapshot. It ended on app close; its
terminal report and independent inspection confirmed the owned container stopped
and all three loopback ports closed. The original session lacks a terminal
report, so its complete lifecycle is not certified. Codacy remains unavailable,
not PASS; broader accessibility remains unverified.
