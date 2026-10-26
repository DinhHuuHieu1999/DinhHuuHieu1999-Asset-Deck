# Asset Desk

Personal equipment inventory built from selected ToolDeck base source.

## Baseline acceptance (before inventory export)

Backend source and unit tests are implemented. Dependencies are installed with
lifecycle scripts disabled and an independent backend lockfile. Typecheck and
112 tests and the rebuilt backend candidate pass using this repository's
installed dependencies, including the startup-cleanup patch.
Separate synthetic PostgreSQL repository and loopback HTTP API fixtures passed
and were stopped. A separate restart/dump/restore fixture also passed.
The real Dart client passed a separate synthetic HTTPS fixture. A local clone of
commit `8e1430c` passed backend typecheck/build, 112 backend tests, 82 Flutter
tests, analyzer and 20 Python/Node fixture-contract tests. That clone did not exercise the native client. The clone needed approved network metadata access
after offline installation failed; locked package archives were reused from cache
and lifecycle scripts stayed disabled.
There is no regular deployment/database. Flutter auth/inventory source
passes analyzer and 86 synthetic unit/widget/harness tests. The Windows release
candidate built successfully after offline plugin metadata generation; the first
attempt failed because `generated_plugins.cmake` was missing. The native process
opened on a separate synthetic HTTPS fixture. The operator confirmed native sign-in, search/filter, create/edit with refresh,
draft keep/discard and sign-out/sign-in persistence on the synthetic fixture.
Native accessibility and error/conflict interaction checks remain pending.
The initial 103 source files are committed as `8e1430c` on
`feat/asset-desk-bootstrap`. The validation clone has no remote and remained
Git-clean after checks. The initial validation did not perform a push or regular
deployment. The Windows runner was subsequently committed in `91ed04e`.
The local remote-tracking ref for `origin/feat/asset-desk-bootstrap` records
`d7b4593`; this statement is not a live remote-state check.

- [Flutter source and verification limits](flutter/README.md)
- [HTTPS fixture scope and evidence](docs/client-https-acceptance-plan.md)
- [Windows native acceptance plan](docs/windows-native-acceptance-plan.md)
- [MVP and acceptance scope](docs/mvp.md)
- [Base extraction decisions](docs/base-selection.md)
- [Source provenance](docs/source-provenance.json)
- [Backend source and verification limits](backend/README.md)

## Inventory export

The current `feat/asset-export-json` source adds complete owner-scoped JSON export,
strict client validation, explicit Prepare and Windows Save As with no overwrite.
Limits are 500 assets and 1 MiB, with no partial export. The baseline list filters
are not export filters. Sensitive plaintext serial numbers/notes are included;
checksums do not prove authenticity and export is not an encrypted database backup.

Export source/tests are committed locally as `16beee5`. Backend typecheck and
127 tests, Flutter analyzer and 138 tests, isolated PostgreSQL/HTTPS concurrency
and Dart-client checks, Windows release compilation and native helper checks pass
at their recorded scopes. The operator confirmed native Save/Cancel and two saved
files passed independent checksum verification. Both fixtures stopped cleanly.
Codacy has a bounded operator-approved local coverage exception, not a security
PASS; screen-reader acceptance remains pending. No export-phase push, regular
deployment, migration or new production dependency was performed.
See [inventory export contract and evidence](docs/inventory-export.md).

The initial MVP excludes AI, team sharing, file attachments and deletion. Import
is a separate optional phase described below, not part of the export operation.
Equipment labels and notes are inert data. Existing ToolDeck accounts/data are not copied.

## Local inventory inspection (source candidate)

The `feat/asset-inspect-json` candidate adds explicit local JSON selection,
strict checksum/record validation and read-only preview, with no import or
backend write. The isolated Windows release builds and 29 native helper assertions pass;
operator dialog acceptance remains pending.
See [inspection scope and remaining native checks](docs/inventory-inspection.md).

## Optional add-only inventory import

Commit `6319ee7` adds an explicitly opt-in import workflow, separate from read-only
Inspect. It validates a complete export, reviews editable fields and adds new
owner-scoped assets without replacing existing records. Defaults remain disabled;
backend enablement requires migration 003 and Flutter requires its compile flag.

Isolated PostgreSQL and HTTPS fixtures verified transaction/replay and ownership
contracts. The operator confirmed Windows import from one to two assets,
sign-out/sign-in persistence, unsent Keep/Discard and picker Cancel behavior.
These checks do not certify native fault-path handling or security coverage.
The earlier import candidate retained request identity in RAM only. An explicit
[private recovery file candidate](docs/inventory-import-recovery-proposal.md) now
has offline source/tests and passed one isolated HTTPS process-reconstruction
check. Its Windows release compiled, but Code Integrity blocked launch; native
recovery acceptance remains pending.
Do not blindly create a new operation after an uncertain write.
No regular deployment or import-phase push has been performed.

See [the import contract and remaining gates](docs/inventory-import.md).

## Inventory category filter

Inventory supports an exact, case-sensitive category filter combined with Search
and Status before pagination. Leave category blank to select all categories;
full JSON export remains independent of list filters.
Source is committed locally as `7311879`; isolated PostgreSQL and HTTPS checks
passed, but Windows native acceptance remains pending. Not deployed.
See [category contract and verification scope](docs/inventory-category-filter.md).

## Optional purchase and warranty dates

Separate owner-scoped date reads/updates preserve the legacy inventory contract.
Backend migration 004 and `ASSET_DATES_ENABLED=true` are explicit prerequisites;
Flutter uses `ASSET_DESK_ENABLE_ASSET_DATES=true`. Both flags default off.
JSON v1 excludes dates and is not a warranty backup. Isolated SQL/HTTPS and
database restart/restore checks passed; Windows native acceptance remains pending.
See [date behavior and verification limits](docs/inventory-dates.md).

## Date-aware inventory JSON v2

Optional export v2 includes purchase and warranty dates in a complete owner-scoped
snapshot, while v1 export/import/recovery remains unchanged. It uses the existing
dates capability flags and migration 004, with no new dependency or migration.
SQL concurrency and real Dart HTTPS checks passed on isolated synthetic fixtures;
Windows native v2 acceptance remains pending. No v2 import or restore is provided.
See [v2 contract and acceptance limits](docs/inventory-export-v2.md).
