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

No AI, team sharing, file attachments, import or deletion is included. Equipment
labels and notes are inert data. Existing ToolDeck accounts/data are not copied.
