# Daily local use plan

Status: proposal only. This document does not authorize provisioning, deployment,
data transfer, or changes to Windows security.

## Intended boundary

Use a separate persistent Asset Desk database and a local account created by the
operator. Do not copy fixture accounts, credentials, or inventory into it.

The proposed connection path is:

```text
Windows app -> localhost HTTPS gateway -> loopback HTTP backend -> PostgreSQL
```

Keep every listener local. Do not change firewall rules, certificate trust, or
Smart App Control. If Windows blocks a new artifact, stop without bypassing it.
Initially use manual startup, not a scheduled task or automatic startup service.

## Runtime prerequisites

- Keep versioned releases separate from private configuration, persistent database
  storage, backups, and redacted logs. Record release hashes and client build flags.
- Select ports and private storage paths before provisioning. Existing fixture
  ports are not a reserved daily-use configuration.
- Use a reviewed HTTPS gateway with ordinary certificate validation. The existing
  `scripts/client-https-proxy.mjs` is test-only and includes recovery fault injection;
  it must not become the daily gateway unchanged.
- Start the backend with its backend directory as the working directory. It binds
  to `127.0.0.1`; do not change its proxy-trust setting implicitly.
- Supply secrets through a private process environment or another explicitly
  reviewed configuration mechanism. Production does not load `.env.local`.
  Follow `backend/env/.env.example`; never print connection strings or secrets.
- Retain CSRF protection, secure cookies, request freshness, and normal throttling.
  Do not copy fixture-specific overrides into daily configuration.

Ignored files are not automatically secure or backed up. Private configuration
requires restricted access and a separate recovery procedure.

## Feature and schema selection

Approve one explicit feature profile before building the client or migrating the
new database. Match backend feature flags to the corresponding client build flags.
Imports remain disabled unless separately selected and accepted.

| Capability                  | Migration prerequisite                    |
| --------------------------- | ----------------------------------------- |
| Accounts and inventory      | `001-auth-accounts.sql`, `002-assets.sql` |
| Import receipts             | `003-asset-import.sql`                    |
| Purchase and warranty dates | `004-asset-dates.sql`                     |
| Location                    | `005-asset-location.sql`                  |
| Check date                  | `006-asset-check.sql`                     |
| Saved filters               | `007-asset-saved-filters.sql`             |

This is an inventory of existing migrations, not an instruction to apply them all.
Review dependencies and selected export versions before choosing the final profile.

## Startup and shutdown contract

A future launcher should validate required artifacts and available ports before
starting anything. It should record process identity, enforce startup deadlines,
and fail closed on an unexpected listener or existing process. Never kill a process
only because it occupies the configured port.

Start the database, backend, HTTPS gateway, then app, checking readiness at each
step. Stop only verified owned processes, allowing graceful backend shutdown.
Closing the app must not delete data or destroy the database volume. Fixture
30-minute expiry behavior is not appropriate for persistent storage.

No daily-use launcher or service installation is approved by this plan.

## Backup and restore acceptance

Full PostgreSQL backups must preserve accounts, assets, import receipts, optional
fields, and saved filters. JSON exports are useful portability artifacts, not a
complete database or account backup.

Before storing real inventory:

1. Create synthetic data in the new isolated daily-use acceptance environment.
2. Restart and verify persistence.
3. Produce a custom-format PostgreSQL dump and a checksum without overwriting an
   existing backup. Capture the application and schema versions.
4. Restore into a different isolated database, failing on restore errors.
5. Compare all selected-domain records and verify login and representative UI flows.

Choose backup destination, retention, and schedule explicitly. A daily backup is a
proposed recovery-point target, not an implemented guarantee. Keep an independently
protected copy where practical; another directory on the same disk does not cover
disk failure. Protect configuration and signing/TLS material separately without
putting secrets into reports or source control.

## Rollback

Retain the previous release and configuration reference. On failure, stop only the
owned app, gateway, and backend. Reuse the previous release only if its database
compatibility is established. Do not downgrade schema, drop tables, or delete data.

If restoration is necessary, restore to a new database, validate it, then obtain
approval before switching the connection. Preserve the original database and failed
artifacts for diagnosis. Disabling optional flags is not a substitute for checking
release compatibility.

## Staged implementation

The first implementation slice should contain source and offline tests only:

- A daily HTTPS gateway separate from fixture routing and fault-injection modules.
  Permit only the configured loopback upstream; reject malformed configuration
  before opening listeners or reading TLS material. Bound requests and shutdown.
- A manual launcher with explicit start/status/stop operations. Identify owned
  processes using more than a PID, refuse ambiguous ownership, and preserve storage
  on every failure path. Never expose secrets through command-line arguments.
- A configuration example containing placeholders only, with no implicit import
  enablement, migration execution, certificate generation, or trust installation.
- Offline tests for invalid paths/ports, missing artifacts, unexpected listeners,
  partial startup failure, ownership mismatch, bounded shutdown, and log redaction.
  Test gateway routing and transport failures using injected transports; do not
  treat mocked transport tests as HTTPS acceptance.

Review this slice before any real startup. Database lifecycle and backup commands
need separately reviewed ownership and restore contracts; do not combine their
implementation with an unreviewed launcher shortcut.

1. Read-only preflight: verify source, installed tools, artifact paths, port choices,
   and TLS suitability without reading secret contents or starting services.
2. Review launcher/gateway/configuration templates and offline tests.
3. Accept startup, shutdown, restart, and backup/restore on synthetic fixtures.
4. Obtain approval to provision a separate empty persistent database and private
   configuration, then build the matching client.
5. Have the operator create an account and accept synthetic daily-use flows before
   entering real inventory.

Each runtime step requires its own confirmed scope. No dependency installation,
certificate trust change, data migration, or remote upload is implied.

## Source implementation status

The daily runtime source is experimental. Synthetic HTTPS restart and base-profile
recovery have passed; daily deployment and real Flutter acceptance remain pending.

| Area          | Current implementation                                                    | Remaining acceptance                                          |
| ------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Configuration | Absolute paths, artifact checks, explicit loopback ports                  | Private ACLs, release manifest, client endpoint/profile match |
| Environment   | Explicit allow-list, fixed security flags, imports off by default         | Selected feature/schema profile and database ownership        |
| Lifecycle     | Ordered startup, retained process handles, bounded waits, no force-kill   | Windows process and abrupt-supervisor-exit behavior           |
| Gateway       | Separate TLS listener, bounded workers/requests, fixed loopback transport | Real TLS, wire timeout, in-flight shutdown behavior           |
| Control       | Foreground start/status/stop/quit, exclusive lock, private stdin shutdown | Complete synthetic session acceptance                         |

The gateway uses Python 3.7+ TLS APIs. No new interpreter or dependency has been
installed. Gateway/app children do not receive backend secrets. Child diagnostics
are discarded; only safe status labels are shown. Operational failure reporting
still needs runtime acceptance.

The backend bootstrap returns its owned application after listen so the supervised
entrypoint can call its existing `close()` method. Direct `node dist/main.js`
startup is unchanged. The GUI must be closed manually before stop completes, to
avoid losing drafts. No database provisioning or backup command is implemented.

### Offline verification

```powershell
python -B -m unittest discover -s scripts -p "test_daily_local*.py" -v
node --test scripts/daily-local-backend.test.cjs
```

Historical committed-base results: 110 Python tests, four Node supervisor tests, 1,025 backend tests
(119 opt-in tests skipped), and backend typecheck pass. Python tests use fake transports/processes,
in-memory HTTP requests, and temporary synthetic lock files; they do not open real
sockets or read TLS material. These counts do not certify live deployment.
Gateway shutdown now waits up to 26 seconds for handlers to drain after closing
the listener; actual Windows/TLS draining remains unverified. Codacy tools are
visible again, but the latest one-file call returned an empty result without
analyzer or file-count evidence; this is not a verified passing scan.

### Configuration and command boundary

`scripts/daily-local-config.example.json` contains placeholders only. Its port
numbers are examples, not reservations. Create the private runtime directory and
review all absolute paths, release provenance, client HTTPS endpoint, and feature
flags before a separately approved fixture. Do not use the example unchanged.

Without `--execute-approved-local`, the launcher validates configuration paths
only. With that flag it acquires the session lock and accepts fixed commands on
stdin; it does not start until `start` is entered. The flag is not operator
approval by itself. Private backend values come from the launching environment,
not argv or the JSON file. Backend `.env` and `.env.production` fallbacks are
refused without reading their contents.

Locks prevent accidental duplicate sessions, not malicious same-account access.
A stale or changed lock is preserved; review process state before any separately
approved recovery. Do not delete locks or terminate processes automatically.

## Remaining limits

Synthetic HTTPS and same-record persistence after backend/gateway restart have
passed through the new launcher. Flutter shutdown, release-profile matching,
and private-directory access remain unverified. Extended-profile synthetic
backup/restore has now passed with two owners; this does not certify native UI
or ordinary daily deployment. Recovery is documented in
[the recovery harness](daily-local-recovery-plan.md). Existing fixture results demonstrate
scoped behavior, not deployment readiness. New Windows artifacts may still be
blocked by application control; do not bypass it. Historical Codacy coverage
exceptions are not a security pass for this runtime. No real credentials, services,
or databases have been used by this source phase. Runtime/recovery source is
committed; no deployment approval is implied.

See [backend runtime notes](../backend/README.md),
[Windows client notes](../flutter/README.md), and the
[HTTPS acceptance boundary](client-https-acceptance-plan.md).

## Named profile source contract (not deployed)

`scripts/daily_local_profile.py` defines explicit `base` and
`inventory-with-saved-filters` contracts. Base keeps all optional flags disabled.
The extended proposal enables dates, location, check date, saved filters and their
full/selection exports; every import version stays disabled. Its schema list is
001 through 007 in order, including the unused import-receipt table to preserve
normal migration ordering. A table existing does not enable its API.

The helper returns fresh metadata and rejects contradictory feature overrides
before constructing the security-preserving backend environment. It neither
executes migrations nor changes launcher defaults. Eight new offline tests bring
the worktree daily group to 118; the committed-source result above remains 110.
The latest worktree result is 152 guarded offline tests plus a separately
approved extended HTTPS recovery fixture: populated/null fields and saved filters
survived restore and reauthentication for two owners. Imports remained disabled.
Client/profile matching and operator profile selection for ordinary daily use
remain pending. Do not start an extended daily session based on this helper alone.

### Client build metadata (source only)

`client_profile_flags(name)` returns the explicit Flutter boolean defines matching
one named backend profile. Both profiles disable local HTTP and every import
version; the extended profile enables optional fields, exports and saved filters.
An offline contract checks the complete boolean-define set against
`flutter/lib/main.dart` and rejects an unmapped backend feature or duplicate client
mapping. Returned dictionaries are independent.

This helper does not build or launch anything. It does not choose an API endpoint,
inspect a compiled executable, or prove that a release used these flags. Review the
HTTPS endpoint and record actual build arguments and artifact hashes separately.
The manual launcher accepts optional `--profile base` or
`--profile inventory-with-saved-filters`. In execute mode it applies that contract
before acquiring a session lock or creating an adapter; conflicting environment
flags fail closed. Omitting the option preserves the existing explicit environment
behavior. Dry-run still validates paths only, not private environment or schema.
This source integration does not verify the client artifact or apply migrations.
Native acceptance and ordinary deployment remain pending.
