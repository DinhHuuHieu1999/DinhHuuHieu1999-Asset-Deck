# Mark checked today

Asset details offers **Mark checked today (UTC)** when check-date support is
enabled and the displayed asset/check versions match. The action opens the
existing check-date editor with the current UTC calendar day prefilled. It does
not write until **Save check date** is pressed. Review or correct the date before
saving; the normal manual editor remains available.

The suggested date is captured when the editor opens, not silently advanced at
midnight. UTC can differ from the operator's local calendar day. Existing
validation rejects future or invalid dates. This is a manual assertion, not
proof that equipment was inspected.

Save uses the verified original version and existing check-date endpoint. Only
the check date changes. Success returns to inventory and reloads applied filters,
page and sort; unsent filter controls are not applied. Keep editing preserves the
draft, while Discard performs no write. Conflict or uncertain outcome preserves
the draft and blocks blind resubmission; no automatic retry is introduced.

No backend, schema, dependency or export-format changes are included. Synthetic
widget/render checks do not establish native Windows or live API acceptance.
