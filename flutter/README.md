# Asset Desk Flutter client source

Source for authenticated personal equipment inventory. No regular deployment or
native acceptance is implied. There is a `main.dart` entry point and Windows runner source rendered from the
installed SDK template. A Windows release candidate built successfully after
offline plugin metadata generation; the functional operator checks below passed on a synthetic fixture.

Implemented: login/register, bounded native JSON transport, CSRF cookie/header,
in-memory bearer session, inventory search/status/pagination and manual create/edit.
Sign-out and HTTP 401 replace the entire private navigator, including draft forms.
Late responses cannot restore an older account or private list. No credentials
are persisted by the client. Inventory remains in memory unless the user
explicitly prepares an export and selects a new local JSON destination.

Failed writes are never retried automatically. Conflicts and unknown write outcomes
preserve the draft and block blind resubmission; return and refresh before another
write. Unknown registration outcomes direct the user to sign in before trying to
register again. Sign-out clears unsaved drafts and does not revoke the server JWT.

## Configuration boundary

| Compile-time setting          | Behavior                                                                 |
| ----------------------------- | ------------------------------------------------------------------------ |
| `ASSET_DESK_API_URL`          | Explicit endpoint ending in `/api/v1`; HTTPS required by default         |
| `ASSET_DESK_ALLOW_LOCAL_HTTP` | Debug-only opt-in for explicit loopback HTTP; ignored in profile/release |

No automatic endpoint discovery, TLS bypass or remembered password is provided.
The client sends `x-request-timestamp` and does not follow HTTP redirects.
Response JSON is bounded to 1 MiB. Password-reset delivery is not configured.
Do not connect this source to a regular backend before isolated acceptance.

## Verification

```powershell
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Analyzer and 86 unit/widget/harness tests pass using the installed SDK/cache. Transport
tests bind an ephemeral loopback HTTP server in-process with synthetic responses;
they do not start the product backend or database and do not certify HTTPS.
Widget tests cover draft keep/discard, stale results, paging, account/session
invalidation and unknown write outcomes. No external production dependency was added.

Synthetic baseline and inventory/auth renders were inspected locally at
390/768/1440 pixels with text scale set to 200%; Material AppBar titles retain
Flutter's built-in scaling clamp. Visible tap-target and label checks pass.
These checks do not replace native or manual keyboard/screen-reader acceptance.
Optional captures use `ASSET_DESK_UI_CAPTURE_FONT`, `ASSET_DESK_UI_CAPTURE_ICONS`
and `ASSET_DESK_UI_CAPTURE_DIR`, referring only to local fonts and ignored output.
The baseline test writes under the product's ignored `.local/flutter-ui`.

A separately approved HTTPS fixture passed using the actual `AssetApi`, default
TLS validation and secure CSRF cookies: two owners, 51 assets, literal search,
status/paging, owner isolation, edit/conflict and fresh-client login. This was a
Dart CLI driver, not the native Flutter UI. The fixture was stopped and retained.
See the [HTTPS acceptance scope](../docs/client-https-acceptance-plan.md).

A local clone of commit `8e1430c` also passed offline pub resolution with the
lockfile enforced, analyzer and all 82 tests using the installed SDK/cache.
The clone remained Git-clean. Backend dependency installation needed separately
approved network metadata access; this was not an entirely offline bootstrap.

The candidate process opened on a separately approved synthetic HTTPS fixture.
The operator confirmed sign-in, literal search/status filtering, create/edit with
refresh, draft keep/discard and sign-out/sign-in persistence. These are manual
functional confirmations, not automated UI observations. The operator also confirmed Tab/Shift+Tab focus and Enter/Space activation.
Native text scaling, screen-reader and error/conflict interaction checks remain pending.
See the [native acceptance plan](../docs/windows-native-acceptance-plan.md).
Source analysis returning an empty result does not establish Dart/security coverage.
The baseline Windows runner was committed in `91ed04e`; export-channel changes
were committed locally in `16beee5`. No fonts, screenshots,
credentials or generated builds are committed.

See [source provenance](../docs/flutter-source-provenance.json).

## Inventory export source phase

Inventory now offers Export all inventory JSON when the store supports exports.
Opening the route does not fetch or save data. Prepare requests the complete
account snapshot independently of list filters and validates checksum/count/bounds.
Save JSON as... opens the Windows dialog; cancellation retains the prepared
snapshot, existing files are not overwritten and errors do not retry automatically.
Sign-out clears the private export route, including pending-result UI updates.

The export contains sensitive plaintext serial numbers and notes, at most 500
assets and 1 MiB. It is not encrypted, authenticated or importable by this client.
No automatic clipboard, upload or persistent session storage is added.

The full offline Flutter suite passed 138 tests, with one opt-in Python bridge
test skipped in that run and separately executed successfully. Analyzer is clean. Synthetic export
renders at 390/1440 pixels and 200% text were inspected. Windows release built from
a selected uncommitted source copy; a separately compiled native helper passed
16 assertions for actual BCrypt vectors and synthetic new-file/no-overwrite writes.
Separate isolated HTTPS acceptance verified the actual Dart client and concurrent
PostgreSQL snapshot behavior. The operator confirmed native Prepare/Save/Cancel;
two saved files passed independent Python checksum verification. These checks do
not certify screen-reader behavior or constitute Codacy/security PASS.
See [export scope and remaining acceptance](../docs/inventory-export.md).

## Optional purchase and warranty dates

Separate owner-scoped date reads/updates preserve the legacy inventory contract.
Backend migration 004 and `ASSET_DATES_ENABLED=true` are explicit prerequisites;
Flutter uses `ASSET_DESK_ENABLE_ASSET_DATES=true`. Both flags default off.
JSON v1 excludes dates and is not a warranty backup. Isolated SQL/HTTPS and
database restart/restore checks passed; Windows native acceptance remains pending.
See [date behavior and verification limits](../docs/inventory-dates.md).

## Date-aware inventory JSON v2

Optional export v2 includes purchase and warranty dates in a complete owner-scoped
snapshot, while v1 export/import/recovery remains unchanged. It uses the existing
dates capability flags and migration 004, with no new dependency or migration.
SQL concurrency and real Dart HTTPS checks passed on isolated synthetic fixtures;
Windows native v2 acceptance remains pending. The separate import-v2 source slice
below is opt-in and does not alter v1.
See [v2 contract and acceptance limits](../docs/inventory-export-v2.md).

### Optional date-aware import v2

The separate review page requires `ASSET_DESK_ENABLE_IMPORT_V2=true`, existing
`ASSET_DESK_ENABLE_IMPORT=true` and `ASSET_DESK_ENABLE_ASSET_DATES=true`,
an authenticated session and a store implementing the v2 import capability.
All feature flags default off. Backend v2 also requires its explicit import/date
flags and existing date schema; see the [v2 proposal](../docs/inventory-import-v2-proposal.md).

Review all fields and dates, save a private recovery file, then acknowledge and
confirm explicitly. Recovery files contain plaintext serials and notes. Reopening
one validates the configured account/backend but never submits automatically;
unknown outcomes permit only explicit replay of the same request/key. Neither
checksum nor an empty analyzer result proves authenticity or security.
See [UI scope and offline evidence](../docs/inventory-import-v2-ui-plan.md).
Windows file-dialog acceptance and regular deployment remain pending.

## Optional warranty filtering

The dates capability adds Expired and Expiring within 30 days filters, intersected
with search/status/category before pagination. Unknown dates match neither;
expiry today belongs to the upcoming window. The UI displays the UTC reference
date and retains it across pages. Failed requests preserve the previous results
with a stale-data notice. Full export and overview are not filtered.

Existing dates flags and migration 004 are required; defaults remain off. No
new dependency, migration, automated notification or regular deployment is added.
Isolated PostgreSQL and real Dart HTTPS checks passed. Windows native acceptance
remains pending. See [warranty contract and evidence](../docs/inventory-warranty-filter.md).

## Optional manual locations (source checkpoint)

`ASSET_DESK_ENABLE_ASSET_LOCATION` defaults to false. The matching backend
`ASSET_LOCATION_ENABLED` requires explicit migration 005. Location editing loads
a fresh shared asset version; unknown outcomes and conflicts preserve drafts
without automatic retry. Location filtering is exact and case-sensitive, or
explicitly unknown, and combines with search/status/category before paging.
Combined warranty filters require the date capability and migration 004.
Inventory JSON v1/v2 exclude location labels and are not location backups.
Source tests and synthetic rendering are not native or database acceptance.

## Optional inventory export v3 (source checkpoint)

`ASSET_DESK_ENABLE_EXPORT_V3` defaults false. Navigation also requires the dates
and manual-location flags. Backend `ASSET_EXPORT_V3_ENABLED` separately requires
both capabilities and existing migrations 004/005; no schema is applied at startup.

Export v3 includes all owner assets, dates and nullable location labels, not the
current filtered page. Prepare explicitly, then use Save JSON as. Inspect v3
validates a local file and previews it without importing or sending it anywhere.
Files contain private plaintext data; a checksum is not proof of authenticity.
V1/v2 remain unchanged and there is no v3 import/restore capability.

Database, HTTPS and Windows acceptance for v3 remain pending. See the
[v3 contract and offline checkpoint](../docs/inventory-export-v3-plan.md).

## Optional inventory import v3 (source checkpoint)

`ASSET_DESK_ENABLE_IMPORT_V3` defaults false. Navigation requires signed-in v3
client capability and the import, dates and manual-location client flags; it does
not require import v2 or export v3. Backend `ASSET_IMPORT_V3_ENABLED` is separate.
Existing v1/v2 behavior remains unchanged. No migration runs at startup.

Choose a verified v3 export, review dates/location and target account, save a
private recovery file, then explicitly acknowledge and confirm. Inspect never
imports. Unknown delivery retains the same immutable request/key; replay is
explicit, never automatic. A recovery file is plaintext and must match the exact
account and endpoint. Cancel does not imply save/submission success.

Synthetic widget/channel tests and renders are not Windows file-dialog acceptance.
See the [UI plan and remaining gates](../docs/inventory-import-v3-ui-plan.md).

## Optional location overview

The existing opt-in location capability adds complete owner counts through
`GET /api/v1/assets/locations/overview` (no query parameters, no-store).
Known labels are exact and case-sensitive; null is the unknown bucket. More than
1,000 known labels or unsafe counts fail instead of returning partial counts.
The Flutter entry selects exact/unknown inventory filters and clears other list
filters explicitly. No migration or dependency is added. Isolated PostgreSQL
and real Dart HTTPS checks passed; the operator confirmed the listed Windows
functional checks. Accessibility and deployment remain separate; see
[the plan](../docs/inventory-location-overview-plan.md).

## Asset details

View details opens the selected inventory snapshot, not a live record. Enabled
date/location reads must match its identity and version; failures never appear as
unknown values. With a read-capable source, Refresh details reads one asset and
verifies enabled dates/location before replacing the entire snapshot. Failure
retains the old snapshot with a stale warning and disables editing until a
successful refresh. Without this capability, refresh inventory and reopen. Back preserves
the inventory filters. The original read-only details checks passed on a synthetic
Windows fixture; screen-reader acceptance and deployment are not implied.

Edit asset from details reuses the existing base-field editor with the selected
record ID and version. Save closes details and reloads inventory with its applied
filters and page; unapplied filter text is retained. Cancel returns to the same
snapshot without a write or reload. Conflicts and unknown save outcomes retain the
draft and block blind resubmission. Date/location verification must finish before
editing is available; base-field editing does not write those optional fields.
The operator confirmed this flow on a separate synthetic Windows fixture: saved
Notes, unchanged dates/location, draft Keep/Discard and Back preserving Search.
Screen-reader checks and regular deployment remain outside that acceptance.
See [scope and verification](../docs/edit-from-asset-details-plan.md).

Enabled purchase/warranty dates and location can also be edited from details.
Each action passes the verified snapshot version to the existing dedicated editor;
Unknown values remain editable, while loading or failed reads disable editing.
Save returns to inventory; Cancel keeps the same snapshot. The operator confirmed saved dates/location, location Keep/Discard and Back
preserving Search on a separate synthetic Windows fixture. Other field isolation
and date-editor draft handling remain widget-tested; screen-reader checks and
regular deployment are not implied. See [scope](../docs/details-optional-edit-proposal.md).

## Inventory overview drill-down

View assets in Inventory overview selects one status or exact category, clears
other inventory filters and loads page one. Back without selection preserves the
previous list and filters. Counts and the loaded list are separate snapshots;
failed loads retain the previous rows and their applied-filter identity.
See the [scope and verification](../docs/inventory-overview-drilldown-plan.md);
the actual Dart client passed isolated HTTPS selection/pagination checks, while
the operator confirmed status/category selection, empty results and Back preserving
search/list on a separate Windows fixture. Dedicated keyboard/screen-reader
acceptance and deployment remain pending.

## Warranty overview actions

View expired assets and View assets expiring within 30 days clear other filters
and load inventory at the overview UTC reference date. Paging and Refresh keep
that reference; explicit Apply requests a fresh date. Later and Unknown remain
informational. Back preserves the prior list and filter drafts.
See [scope and verification](../docs/warranty-overview-drilldown-plan.md).

## Inventory sorting source candidate

Sort inventory offers Recent updates (legacy default) and Name A-Z. Apply starts
page one; Refresh and paging retain the last successful sort, and failed loads
retain its identity with old rows. Overview selections preserve applied sort;
Back does not apply a draft. Ordering is server-side, with a stable ID tie-breaker.
Name sorting uses case-sensitive PostgreSQL C collation, not natural locale order.
See the [sort acceptance plan](../docs/inventory-sort-plan.md). No new database
fixture, native acceptance, commit or deployment is claimed for this phase.

## Filtered selection export

The separate selection parser/client preserves applied filters and rejects
response scope mismatch. Its format is not a full-inventory backup and is not
accepted by existing full export/import parsers. Isolated HTTPS and functional
Windows Prepare/Save/Cancel/Back checks passed; screen-reader acceptance and
Codacy analyzer coverage remain pending; see [selection export plan](../docs/inventory-selection-export-plan.md).

## Read-only selection inspection candidate

With the existing selection export, dates and location feature flags enabled,
**Inspect selection JSON (no import)** opens a separate local file preview.
The bounded reader accepts only the selection format, validates the exact payload
checksum and shows its recorded filters and assets. It does not query the backend,
verify that records match those filters, or import anything. A checksum is not proof
of authenticity; the file is a snapshot, not a full inventory backup.

Cancel preserves the previous preview. Selecting an invalid file clears previous
records and checksum evidence; signing out removes the route. The Windows picker
is reused without a new dependency. On a separate synthetic Windows fixture, the
operator confirmed selection preview, Cancel retaining preview/checksum, and an
invalid file clearing both. Screen-reader acceptance and Codacy analyzer coverage
remain pending. No deployment is implied.

## Reset inventory filters

Reset filters clears search/status/category/warranty/location on successful load,
returns to page one and keeps the applied sort, not an unapplied sort draft.
Failure retains the previous applied results and draft controls; no asset is
written. The operator confirmed reset keeping applied sort, Refresh persistence and
recovery from invalid Exact location on a synthetic Windows fixture. Failure
preservation and page-two reset remain widget-tested; native keyboard/screen-reader
checks and deployment are not implied.
See [behavior and checks](../docs/inventory-reset-filters.md).

## Advisory serial duplicate check

The manual editor can explicitly check an exact, case-sensitive serial against
the signed-in account inventory. A duplicate or unavailable check never blocks
Save. Editing Serial clears the previous result; no automatic check or retry runs.
The optional capability leaves legacy/test stores unchanged.

See [serial warning contract](../docs/inventory-serial-warning.md) for limits and
verification scope. Not deployed or native-accepted.

## Manual check-date candidate

`ASSET_DESK_ENABLE_ASSET_CHECK` defaults to false. When enabled with the matching
backend feature, Details can read/edit a manual check date and inventory can filter
unknown dates. Unknown includes cleared dates; it does not prove an asset was
never checked. Existing JSON exports exclude this field; matching selection export
is unavailable while this filter is applied. Migration and live/native acceptance
remain separate rollout gates. See [the source plan](../docs/asset-last-checked-plan.md).

## Optional inventory import v4

`ASSET_DESK_ENABLE_IMPORT_V4` defaults false. Navigation requires a signed-in
v4 import capability plus the import, dates, location and manual-check client
flags. Import v2/v3 and export flags are not prerequisites. Backend
`ASSET_IMPORT_V4_ENABLED` is independent and defaults false.

The separate v4 page reviews nullable manual check dates as well as dates and
location. Save private recovery JSON before explicit confirmation; an uncertain
outcome retains the exact request/key for explicit replay. V1-v3 remain unchanged.
See the [v4 proposal and current acceptance limits](../docs/inventory-import-v4-proposal.md).
Synthetic HTTPS recovery fault injection passed; native Windows acceptance is
still pending because Code Integrity blocked the candidate executable. This does
not certify native dialogs or deployment.
