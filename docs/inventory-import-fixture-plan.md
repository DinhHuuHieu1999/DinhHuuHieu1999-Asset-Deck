# Inventory import PostgreSQL acceptance plan

Status: one separately approved isolated run passed all seven scenarios. Its
container is stopped and volume retained. Further execution requires new approval;
default test runs still skip the database suite.

## Scope

One new fixture using a locally available PostgreSQL image by immutable image ID;
never pull an image. Create a uniquely named container, volume and synthetic
credentials, with an ownership label/marker and a dedicated database named
`asset_import_fixture_<12 hex>`. Publish one random port only on 127.0.0.1.
Do not mount source, host data or real credentials into the container.

Apply only this repository's migrations 001/002/003 to the new database. Create
`public.asset_import_fixture_identity` with the generated marker before invoking
the dedicated repository suite. No product backend, HTTPS listener, native app,
provider or regular database is involved.

## Run and acceptance

Invoke only `asset-import.postgres.spec.ts` with the exact opt-in and dedicated
fixture variables described in [the import contract](inventory-import.md).
Use the installed dependencies; no install, build, retry or remote service.
Bound the whole Jest process to 120 seconds; per-connection/statement limits are
five seconds. Readiness commands must also have bounded deadlines. Require TCP on 127.0.0.1
and an exact `current_database()` result; socket availability can observe the
entrypoint temporary initialization server and is not sufficient readiness.

Require all seven scenarios to pass: 500-row exact replay, changed-content
conflict, independent owners, identical concurrent requests, conflicting
concurrent requests, complete rollback on a fixture trigger error, and exact
replay after a real COMMIT with a synthetic missing acknowledgment. Counts and
receipt IDs must prove no duplicate or partial writes. Source checks are not
runtime proof; failed or skipped scenarios remain failed/pending.

## Retention and cleanup

Record image ID, resource IDs, ownership labels, timing, exit status and sanitized
test results in local ignored evidence. Keep generated credentials local and do
not print connection URLs or raw records. On success or failure, independently
verify ownership before stopping the fixture container. Retain its stopped
container and volume; do not delete resources or alter the regular backend.
If image availability, binding, ownership or safety prerequisites fail, stop and
report without retry. Test-only trigger/function remain in the retained database.

This fixture does not certify HTTP authentication, CSRF, TLS, native Windows,
backup/restore, UI accessibility or persistent client recovery. Those remain
separate gates and do not inherit this approval.
