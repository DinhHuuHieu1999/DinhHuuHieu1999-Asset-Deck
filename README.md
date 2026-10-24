# Asset Desk

Personal equipment inventory built from selected ToolDeck base source.

## Current status

Backend source and unit tests are implemented. Dependencies are installed with
lifecycle scripts disabled and an independent backend lockfile. Typecheck and
112 tests and the rebuilt backend candidate pass using this repository's
installed dependencies, including the startup-cleanup patch.
Separate synthetic PostgreSQL repository and loopback HTTP API fixtures passed
and were stopped. A separate restart/dump/restore fixture also passed.
The real Dart client passed a separate synthetic HTTPS fixture. Clean-checkout
and native client acceptance remain pending.
There is no regular deployment/database. Flutter auth/inventory source
passes analyzer and 82 synthetic unit/widget/harness tests. No platform runner
has been generated; Windows/native acceptance remains pending.
The local Git repository uses `feat/asset-desk-bootstrap`; nothing is committed,
staged or connected to a remote.

- [Flutter source and verification limits](flutter/README.md)
- [HTTPS fixture scope and evidence](docs/client-https-acceptance-plan.md)
- [MVP and acceptance scope](docs/mvp.md)
- [Base extraction decisions](docs/base-selection.md)
- [Source provenance](docs/source-provenance.json)
- [Backend source and verification limits](backend/README.md)

No AI, team sharing, files, imports/exports or deletion is included. Equipment
labels and notes are inert data. Existing ToolDeck accounts/data are not copied.
