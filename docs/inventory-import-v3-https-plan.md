# Inventory import v3 HTTPS acceptance plan

Status: one approved normal HTTPS fixture completed on 2026-10-28 after a
backend candidate build. Separately approved disabled-route and response-loss
recovery fixtures also completed. Scoped Windows interactions were confirmed by
the operator; see the [UI record](inventory-import-v3-ui-plan.md) and
[recovery record](inventory-import-v3-recovery-plan.md). These results do not
certify deployment, accessibility or Codacy acceptance.

## Fixed profile

The dedicated runner is `scripts/import-v3-https-fixture.py`. It selects only the
exclusive boolean import-v3 lifecycle profile. Missing client source or built
backend artifacts refuse before Docker creates resources. The child backend
explicitly enables import, dates, location, export v3 and import v3, with import v2
disabled. Export v3 is enabled for test round-trip verification, not a production
prerequisite of the import endpoint. Old profiles explicitly disable import v3.

Apply existing migrations 001/002/003/004/005 only to a new synthetic database.
Reuse the labelled container/volume lifecycle, three distinct loopback ports,
already-present immutable PostgreSQL image and existing localhost certificate.
Default TLS certificate verification remains enabled. No pull/install, regular
backend/database, trust/firewall/SAC change, native UI or provider/model access.
The execution budget is 300 seconds with no acceptance retry; cleanup has a
separate bounded budget and retains owned stopped resources and local evidence.

## Real client assertions

The Dart driver verifies the exact synthetic marker before registering two owners.
It creates an asset, sets dates/location, exports a checksum-verified v3 snapshot
with an independent Python SHA-256 implementation, and imports into the other
account. Exact replay must return the same IDs without duplicate assets. A complete
re-export must preserve every editable base field, dates and location under fresh
IDs with version 1. Date-only and location-only changes under the same key must
conflict; the imported record must remain unchanged. Same-key imports by different
owners remain separate. A draft bound to another account or signed-out session
must not be sent. Only exact, typed summary output counts as acceptance.

Negative HTTPS cases cover unauthenticated and missing-CSRF requests, malformed
JSON, empty batches, owner overrides, invalid dates, omitted date/location keys,
invalid location controls, duplicate keys and an oversized body. Assets/receipts
must remain unchanged. The oversized-body assertion is a proxy bound, not proof
of the backend raw-body limit. A separate `--disabled-v3-route` execution profile
requires authenticated POST to return 404 without invoking the Dart import driver.
No disabled-route run is implied by the normal profile.

The proxy forwards only exact opted-in POST `/api/v1/assets/import/v3`; route
aliases and v2 are not forwarded by that profile. Normal profiles do not enable recovery response-loss injection. The separate
[recovery harness candidate](inventory-import-v3-recovery-plan.md) requires a
dedicated CLI and explicit request key; its live acceptance remains pending.
This slice does not establish restart, recovery, Windows or deployment acceptance.

## Offline checks

```powershell
python -B -m unittest discover -s scripts -p 'test*https_fixture.py' -q
node --test scripts/client-https-proxy.test.mjs
```

Flutter driver comparison tests mutate every base field, date, location, version
and identity to prove incomplete re-exports are refused. These tests do not execute
the driver's network entry point. Existing Dart API tests use a synthetic local
HTTP server, not the product backend or HTTPS. Native dialogs remain untested.

## Observed normal HTTPS acceptance

Fixture `56ce69acf74a4b1a6b3c56f891200b65` completed once, without retry,
on loopback ports 59441/59442/59443 using the existing pinned PostgreSQL image and
localhost TLS material. The actual Dart client passed exact replay, full re-export,
location/date preservation, separate location/date-only conflicts, two-owner
isolation, account binding and session invalidation. All negative HTTP assertions
passed with unchanged asset/receipt counts. The final checkpoint is `completed`.

Local ignored evidence is under
`.local/asset-client-56ce69acf74a4b1a6b3c56f891200b65/` (`result.json`,
`import-checkpoint.json`, source hashes and lifecycle milestones). Independent
Docker inspection confirmed the matching ownership labels, stopped container,
loopback-only DB port and a retained named volume without host data bind mounts.
No regular backend/database, trust, firewall or SAC configuration was changed.

The previous requested ports were refused before resource creation because they
fell inside a Windows TCP exclusion range. That attempt was not retried; this run
had separate operator approval and used rechecked replacement ports. The normal
profile does not establish disabled-route 404, restart/recovery or native UI
acceptance. No commit, push or deployment was performed.

## Observed disabled-route acceptance

One separately approved HTTPS fixture used the existing backend candidate with
import v3 disabled. An authenticated valid import POST returned 404; asset and
receipt counts were unchanged. Fixture `2f89ff30ab0f402180aee6cf57a99ece`
completed and stopped its owned container, retaining the matching volume and
local evidence. No build or retry was performed. This checks route availability
and row counts, not arbitrary byte-level database immutability or deployment.
