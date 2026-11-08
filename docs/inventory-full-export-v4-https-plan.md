# Full export v4 HTTPS client acceptance

## Boundary

A separately approved backend build and one synthetic HTTPS run completed
successfully. The real Dart client passed the assertions below. The owned
container was independently verified stopped and all three fixture ports closed.
Future runs require separate approval.
The fixed entry is `scripts/export-v4-https-fixture.py`; it never builds, pulls an
image, installs dependencies, retries a failed run or opens a native application.

## Planned fixture

Use an existing immutable PostgreSQL image, new synthetic owned container/volume,
three distinct loopback-only ports and an existing localhost certificate/key.
Keep default TLS verification; do not change trust, firewall or Windows security.
The existing lifecycle has a 300-second deadline and bounded owned cleanup.
Retain stopped resources and evidence. Never connect to a regular database.
Missing v4 compiled artifacts must refuse before resource creation.

## Driver assertions

- Marker-bound TLS endpoint, two synthetic authenticated owners and anonymous 401.
- Raw export success includes no-store; unexpected query parameters receive 400.
- Empty export, 51 records, exact Unicode, location, nullable dates and manual date.
- Manual date update to 2024-03-01 persists through the real Dart v4 parser.
- Python SHA-256 recomputes the exact UTF-8 payload locally, without upload.
- Owner isolation, unchanged v1/v2/v3 schemas, no leakage of manual date into v3.
- List filters do not reduce full export; repeated exports leave rows unchanged.
- Signing out refuses export before digest execution.

The test-only proxy enables v4 explicitly, allows only GET on its export route,
permits required date/location/check editing and keeps import routes disabled.
Invalid or partial driver output fails acceptance. Diagnostics retain a fixed
stage only, not credentials or payloads. Native dialogs remain outside this run.

## Offline evidence

Seven new Python orchestration/profile tests passed, including mocked lifecycle
flag wiring and ownership cleanup. Shared HTTPS regressions and 44 proxy tests
passed. Two Dart HTTP-validator tests and Flutter analyzer passed. None of these
offline claims alone constitutes real HTTPS or Windows acceptance. The later
operator-approved real HTTPS run passed. The separate
[Windows plan](inventory-full-export-v4-native-plan.md) records later operator
checks; this HTTPS run alone does not certify native dialogs.
