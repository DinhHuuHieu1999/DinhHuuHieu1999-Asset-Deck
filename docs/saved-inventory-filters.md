# Account-owned saved inventory filters

Status: isolated PostgreSQL, HTTPS and operator Windows checks passed;
isolated database restart/restore and backend restart checks passed.

Optional ASSET_SAVED_FILTERS_ENABLED defaults to false. Enabling requires
migration 007 applied separately, after migration 001/002. Startup checks the
saved_filters table; it never creates it. Disable the flag to roll back runtime
exposure while retaining saved definitions. No new production dependency.

The authenticated /api/v1/inventory-saved-filters collection accepts GET and
POST; /:id accepts PUT and DELETE. Mutations retain global CSRF protection.
Owner is always taken from authentication, never submitted. All responses are
no-store. POST accepts name, schemaVersion: 1 and a complete query. PUT
additionally needs version. DELETE accepts only version. Unknown fields are
rejected. Missing and foreign IDs return the same not-found response; stale
versions return conflict. Names trim to 1-60 characters; duplicates are allowed.
Capacity is 20 per owner, serialized by locking the account row in a transaction
before counting/inserting. Saves/updates are not retried after uncertain commit;
reload before deciding.

Schema v1 records search, status, category, sort, location mode/label, warranty
mode/reference date and check mode/cutoffs. Active dates are fixed Gregorian
YYYY-MM-DD values. Inactive dependent fields must be empty. No offset, token,
asset rows or owner data is accepted in query definitions. Unsupported active
capabilities refuse creation/update rather than silently dropping conditions.
Read-only listing does not apply definitions to inventory or change equipment.

The Flutter ASSET_DESK_ENABLE_SAVED_FILTERS define defaults off. With it
enabled, Saved filters opens account-owned definitions. Save uses the last
successfully applied query, including after a later failed load; unsent controls
are excluded. Use as draft fills controls without fetching. Explicit Apply
fetches page one. Fixed warranty references are labelled in the draft and
preserved on Refresh. Capability-off views remain visible but cannot be used or
renamed. Before and on-or-after check cutoffs require their specific client
capability; unsupported conditions are never silently removed. Delete affects
only the saved definition, with confirmation. Rename preserves the stored query.
After an uncertain write or failed reload, writes require a successful Reload.
The private navigator is replaced on account change; no device preference/cache
is introduced. List responses use a bounded items envelope (maximum 20 IDs).

The collection uses a separate path to avoid collision with /assets/:id. Saving
filter text can retain private search/location labels in the database; these
definitions are not encrypted exports or an asset backup. Existing backup
policy must be reviewed before rollout; only the isolated restore scope below
is verified.

Offline tests currently cover validation, owner-bound SQL and transaction order,
capacity refusal, stale/missing mutations, opt-in configuration and readiness.
Offline tests alone do not prove locking or HTTP behavior. Separate isolated
PostgreSQL and HTTPS runs passed the scenarios below. Accessibility remains
unverified. Operator Windows checks passed
Save, Use as draft, Apply/Refresh, rename, Cancel/delete and unchanged assets. Further
fixtures, builds, deployment and commit remain separate approval boundaries; no
Codacy/security PASS is claimed.

## Source verification

Focused offline coverage includes strict schema and calendar validation,
transaction ordering and capacity failure, stale/missing version handling,
mutation result invariants, opt-in readiness, synthetic client auth/CSRF
transport, malformed response refusal (including changed mutation
names/queries), Save/rename/delete Cancel, applied versus draft query and failed
reload behavior. Synthetic renders at 390/768/1440px with 200% text check
reflow; they do not certify Windows fonts, dialogs or screen readers.

Still required: production backup policy review and
scoped Codacy review. Operator Windows checks passed at the scope above. SQL concurrency and HTTPS checks are
bounded to the explicit scenarios below, not every possible filter combination.
No earlier phase coverage exception applies automatically.

## Isolated PostgreSQL harness

`scripts/saved-filters-postgres-fixture.py` is opt-in and uses the existing
owned lifecycle. A separately approved run requires an already-present immutable
PostgreSQL image, a fresh synthetic database/container/volume, one loopback port
and a 120-second deadline. No pull, mount of real data or automatic retry is
allowed. Ownership is checked before stopping; resources and evidence remain.
Only migrations 001, 002 and 007 are applied inside that new fixture.

Four repository scenarios cover owner isolation and literal/fixed-date
round-trip, concurrent capacity at twenty definitions, concurrent
replacement/stale deletion, and definition-only deletion with committed-state
visibility. Constructing a new repository is not proof of backend restart or
database restore durability. One approved isolated run passed all four scenarios
and stopped its owned container; retained evidence is local only. This does not
certify HTTPS, restart or restore. Default Jest runs skip all four scenarios
without creating a pool. Offline lifecycle tests check opt-in refusal, every
required source, bounded execution and rejection of partial/skipped results;
they do not execute Docker or SQL.

## Isolated HTTPS acceptance

`flutter/tool/saved_filters_https_acceptance.dart` verifies an exact random
fixture marker over normal TLS before registering two synthetic accounts. It
checks literal/fixed-date round-trip, owner isolation, rename, stale deletion
and final deletion through the actual Dart client. It prints only stage/status
and counts, never tokens, credentials or saved text. Writes are not retried.
Offline tests cover target refusal and changed-definition refusal. The source
lifecycle now wires migration 007 and the saved-filter flag only for an explicit
profile. Proxy routes remain off by default and accept only the exact
collection/UUID paths and intended methods. The harness checks unauthenticated
GET refusal and missing-CSRF refusal for POST/PUT/DELETE, then verifies no saved
definition was created. Offline tests inspect the exact request sequence and
omitted CSRF headers; one approved isolated live run passed these checks and the
Dart client flow. Owned backend/proxy processes and the database container
stopped afterward. This is not a full security audit or native Windows
acceptance.

## Opt-in database recovery harness

The saved-filters PostgreSQL runner accepts `--verify-recovery` only with its
existing explicit synthetic opt-in and immutable local image. The source helper
compares all definition columns (including query, owner and version), all asset
columns and owner IDs before/after database-container restart and restoration
into a new database in the same owned container. It requires nonempty assets
and saved definitions from at least two owners, retains an exclusive custom
format dump and refuses existing evidence, malformed data or any changed digest.
It never drops a database, overwrites evidence or retries a failed restore.
The existing 120-second total runtime and ownership-checked cleanup still apply.

Offline command-contract tests do not run Docker or prove restoration. One
separately approved isolated live run passed all four repository scenarios,
database restart and fresh-database restoration. The canonical digest matched
22 definitions, one asset and five owner IDs at all three stages. Its owned
container stopped; volume and dump were retained. No retry was performed. This harness restarts PostgreSQL, not the
backend process; it does not certify API sessions after restart, schema/index
parity, production backup policy or cross-version PostgreSQL restore.

## Isolated backend restart acceptance

`scripts/saved-filters-restart-https-fixture.py` uses the fixed Saved filters
HTTPS profile with a 180-second scenario deadline. Prepare creates two synthetic
owners, one asset and one saved definition each. Private credentials and expected
public fields are retained exclusively in the ignored fixture directory. A new
Dart process reauthenticates after restart and compares each owner's definition
ID/name/query/version and asset ID/content/version/timestamps. Normal TLS and the
random fixture marker are required before any registration or file access.

Restart uses only the exact live backend process handle, its original in-memory
command/environment and matching PID/port/fixture readiness marker. It never
searches or stops processes by name. Failure to stop or establish new readiness
refuses acceptance; shared cleanup still owns all original/replacement handles.
Offline tests do not execute this flow. One separately approved isolated run
passed Prepare, exact-handle backend restart and fresh Dart-client verification
for two owners. Definitions and public asset fields matched; owned processes
and container stopped, with retained fixture data and no retry. Tokens are not persisted and the
fresh-client check does not prove survival of an existing authenticated session.
