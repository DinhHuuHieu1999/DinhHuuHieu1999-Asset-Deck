# Filtered inventory CSV

CSV is a spreadsheet convenience projection of the verified selection JSON v2
snapshot, not an import format, checksum envelope or account backup. It includes
all matching assets, not just the current page. Existing selection limits remain
500 assets and 1 MiB; CSV output also refuses more than 1 MiB. JSON is unchanged.

After Prepare selection JSON, Save selection CSV uses that same immutable
snapshot, without another API request or database write. Unsent inventory draft
controls are excluded by the existing applied-selection boundary. Save is explicit;
Cancel retains the prepared snapshot. The Windows dialog suggests
`asset-desk-inventory-selection.csv`, accepts a new local CSV destination only and
does not overwrite existing files. No automatic retry or private-path logging.

Columns: id, name, category, serial, status, notes, purchasedOn, warrantyExpiresOn,
location, lastCheckedDate, version, createdAt, updatedAt. Unknown optional values
are empty. Output uses UTF-8 without BOM, comma separators, CRLF row endings,
quoted cells and doubled embedded quotes. Embedded newlines remain inside quotes.

Formula-like cells (including leading whitespace/control and full-width formula
markers) receive an apostrophe prefix. This intentionally changes those CSV cell
values; JSON retains exact data. Quoting alone is not formula protection. Do not
remove prefixes or assume protection survives editing and resaving in other tools.
Import CSV explicitly as UTF-8 and text columns to preserve leading-zero serials,
Unicode and ISO dates. Spreadsheet auto-formatting and native dialogs still need
separate operator acceptance. Sensitive serials, notes and locations are plaintext.

Source/unit/widget and synthetic-render checks do not certify Excel behavior,
Windows compilation or actual filesystem writes. No dependency, migration,
backend deployment, import CSV or cloud upload is introduced.
