# Asset Desk backend

Product-owned NestJS API with PostgreSQL-only account storage and assets.
Selected base source comes from ToolDeck commit
`79e22d0fca9281710c782a9abe7ab151d76b6ef4`; see
[provenance](../docs/source-provenance.json).

## API contract

All paths use `/api/v1`. Protected endpoints use existing bearer authentication.
Writes require the existing CSRF cookie/header pair and request timestamp.
Registration/login/reset endpoints retain the base public-auth behavior, not an
exemption from global CSRF middleware or throttling. No account directory,
administrative API or shared inventory is exposed.

| Operation | Endpoint                          | Behavior                                               |
| --------- | --------------------------------- | ------------------------------------------------------ |
| Create    | `POST /assets`                    | New server UUID, owner and version; duplicates allowed |
| List      | `GET /assets?q=&status=&offset=0` | Owner-scoped literal search/filter; 50 rows per page   |
| Replace   | `PUT /assets/:id`                 | Full input plus expected positive integer `version`    |
| CSRF      | `GET /csrf-token`                 | No-store token and configured cookie                   |
| Readiness | `GET /health`                     | Generic readiness, no account/connection details       |

Asset fields: `name` (1-120), `category` (1-64), `serial` (optional, up to 120),
`notes` (optional, up to 2000), `status` (`in_use`, `stored`, `repair`, `retired`).
Required text must be nonblank after trimming; NUL and unknown fields fail.
Optional text defaults to an empty string; explicit null is invalid.
Owner, ID, timestamps and create-version cannot be submitted.

List ordering is newest-updated then UUID descending. Search covers name,
category and serial, not notes. `%` and `_` are literal characters. Filter/search
apply before pagination. Offset above 100000 is invalid; continuation beyond that
boundary fails explicitly with 422 rather than pretending the list is complete.
Edit conflict and unavailable/non-owned record both return 409 without disclosing
another owner's record. Requests are not automatically retried.

## Inventory export source

`GET /assets/export` returns an owner-scoped complete JSON snapshot, with explicit
500-record and 1 MiB envelope limits. It does not reuse filtered list pages.
See [the export contract and pending acceptance](../docs/inventory-export.md).
This addition is source/unit-test evidence only; no new database or HTTPS fixture
has run for export, and no regular backend was updated.

## Runtime and schema gates

No regular product database or backend service has been started; all live
checks used separately owned synthetic fixtures. The migrations
were applied only to a separately approved synthetic PostgreSQL fixture: `migrations/001-auth-accounts.sql`, then `migrations/002-assets.sql`.
Startup checks schema access but never applies DDL. Do not point the new product
at ToolDeck's regular database or reuse its account rows/secrets.

Start from the app-owned `env/.env.example` only after separately approved setup.
Provide independent PostgreSQL credentials and random JWT/CSRF secrets. Do not
commit local env. The entrypoint rejects absent/short signing and CSRF secrets,
disabled CSRF and reset-token exposure. The inherited reset workflow has no mail
delivery integration here; do not advertise self-service email recovery as ready.

The current entrypoint binds HTTP to loopback only (default port 8180), with
proxy trust disabled and no CORS enablement. HTTPS termination/configuration is
not implemented or certified by this slice. Release Windows clients need valid
HTTPS; never bypass TLS validation. No trust, firewall or listener changes were
made on the development machine.

## Commands after dependency setup

Dependency installation was approved and completed with pnpm 11.24.0 using
`--ignore-scripts --ignore-workspace --package-import-method copy` and a
product-local ignored store. `pnpm-lock.yaml` records the independent resolution.
Typecheck, tests and the rebuilt TypeScript candidate pass with these installed
dependencies, including the startup-cleanup patch.
This is not a clean-checkout or deployment acceptance result:

```powershell
pnpm --dir backend typecheck
pnpm --dir backend test
pnpm --dir backend build
```

`pnpm --dir backend start` opens storage/network and is not part of offline source
verification. No lifecycle scripts or product start commands were run.

## Current verification

- Strict TypeScript check passed with the independently installed toolchain.
- 14 Jest suites, 112 tests passed with this repository's installed dependencies.
  Earlier borrowed-toolchain results are superseded for this source/unit gate.
- Dependency installation used exact direct versions already selected from the
  base. Transitive versions are captured in the new lockfile; no package upgrade
  or lifecycle-script execution was requested.
- Post-install Codacy Trivy returned success with an empty result; this is not
  a full security certification.
- Tests include inherited auth/JWT/CSRF/account-storage regressions, PostgreSQL
  mock composition and asset validation/owner/version/query boundaries.
- IP-whitelist tests use transient local HTTP requests; they do not start the
  product backend or contact a real database/provider.
- A separate PostgreSQL 17 fixture passed both migrations, compiled repository
  create/read/update, two-owner isolation, literal search, 52-row pagination,
  filter-before-pagination, concurrent optimistic updates and SQL constraints.
  Its owned container was stopped and its volume retained; no regular data was used.
- Mock bootstrap regressions verify closing an app after startup failure, preserving
  the original failure if cleanup also fails, and retaining a successful listener.
- A new API fixture passed with authenticated TCP database readiness: two-account
  registration/login, real password/JWT flow, anonymous rejection, CSRF and
  freshness enforcement, owner-input rejection, create/search/update and stale
  version conflicts. Final storage held exactly two accounts and one asset.
- The API fixture used HTTP loopback with `CSRF_COOKIE_SECURE=false` only in its
  child environment. No regular configuration was changed; this is not release
  transport or browser cookie acceptance. Its backend/container were stopped
  and volume retained. The earlier preflight failure remains historical evidence.
- A new recovery fixture passed PostgreSQL/backend restart and custom-format
  dump/restore into a second synthetic database. Canonical hashes of all account
  and asset rows matched before restored login. Both original accounts logged
  in; edited asset fields/version, owner isolation and stale-edit rejection held.
  The source remained unchanged during restore; both backends/containers were
  stopped, retaining the dump and two volumes.
- Docker changed the random host port during restart; the harness verified and
  refreshed the mapping before reconnecting. The earlier failed attempt remains
  historical evidence and is not counted as acceptance.
- The actual Dart client passed a separately approved HTTPS fixture with secure
  CSRF cookies, two owners and 51 assets. The fixture proxy terminated TLS without
  changing backend proxy trust. See the [scope and limits](../docs/client-https-acceptance-plan.md).
  Clean-checkout deployment and native Windows acceptance remain pending.
- Codacy is tracked separately while scans finish; an empty result does not
  certify full security or unsupported analyzer coverage.

The next verification gates are clean-checkout validation and separately
approved native client acceptance. No destructive migration rollback
is provided: disable the product/module and retain schema/data on failure.

## Optional add-only import (source in progress)

`ASSET_IMPORT_ENABLED` defaults to `false`. The exact value `true` registers the
separate authenticated import module and requires migration 003 readiness;
startup never applies migrations. Do not enable it on a regular database until
isolated SQL/API acceptance is approved and complete. See the
[import contract and pending gates](../docs/inventory-import.md).

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
Windows native v2 acceptance remains pending. No v2 import or restore is provided.
See [v2 contract and acceptance limits](../docs/inventory-export-v2.md).
