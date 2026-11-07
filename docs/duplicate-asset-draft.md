# Duplicate asset as draft

From verified Asset details, Duplicate as draft opens the existing Add form with
name, category, status and notes copied from the displayed snapshot. It does not
copy serial, identity, owner, version, timestamps, purchase/warranty dates,
location or manual check date. These are separate physical assets, not linked
records. The source asset is never updated by this operation.

Opening the draft performs no mutation. Save explicitly calls the existing create
endpoint; no update, automatic retry, dependency or migration is introduced.
Normal validation and optional exact serial checking still apply. A blank serial
is allowed. Review copied notes/status for suitability before saving.

Back asks Keep editing or Discard even when copied fields have not been changed.
Cancel/discard returns to Details without an inventory reload. Confirmed creation
returns to inventory and reloads the previously applied filters, not unsent draft
controls. The new asset may not match those filters. A failed save retains the
draft and existing unknown-write safeguards. Session changes invalidate Details.

Synthetic source/widget/render checks are not native or backend acceptance. The
CSV phase's approved Codacy exception does not cover these files. No deployment,
fixture, Windows build, commit or push is implied by this source change.
