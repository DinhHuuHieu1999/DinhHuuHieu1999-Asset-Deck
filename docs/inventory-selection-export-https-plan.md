# Selection export HTTPS acceptance plan

Status: source preparation implemented, not executed. The fixed wrapper, Dart
client driver, typed result contract, exclusive lifecycle profile and proxy route
have offline regression coverage. Actual HTTPS/native acceptance remains pending.

## Fixed scope

Reuse the owned synthetic HTTPS lifecycle with an explicit selection profile.
Require an existing immutable PostgreSQL image, fresh synthetic database and
volume, loopback-only ports, existing localhost TLS and default client certificate
validation. Do not pull, install dependencies, change trust, target a regular
database or automatically retry. Verify ownership before stopping resources;
retain evidence and volume. Keep imports disabled.

Before resource creation, preflight every required source and compiled artifact,
including selection controller/config/module/repository/serializer, dates and
location prerequisites, the Dart driver and checksum helper. Reject conflicting
profiles and invalid arguments before creating output. Do not read TLS keys
while merely preparing or testing source.

A later approved build/execution must have a bounded lifecycle deadline and use
exactly one fixed Dart driver invocation. Do not infer runtime success from
these offline tests or the separately passed PostgreSQL fixture.

## Required driver evidence

The report validator is `scripts/selection_export_https_contract.py`. It requires
all thirteen named checks, exact fields and actual boolean values:

- Anonymous access denied; authenticated responses use `Cache-Control: no-store`.
- Invalid/unknown/paging queries rejected, without exposing private response data.
- Two-owner isolation and all 51 matches across a list-page boundary.
- Literal percent/underscore search and combined applied filters.
- Empty intersection produces an empty selection, not a full export.
- Scope, dates and location preserved; exact payload checksum verified using the
  existing bounded Python-stdin oracle, not a production subprocess dependency.
- Existing full export semantics unchanged; inventory records unchanged by export.
- Signed-out client cannot export.

The driver must compute these checks from assertions on actual responses; it
must not emit constant successful checks before those assertions finish. An
exception, timeout, malformed report, omitted check or extra field fails closed.
Persist only allowlisted stage diagnostics, not cookies, credentials or payloads.
Native save dialogs remain outside this fixture's acceptance.

## Offline validation

```powershell
python -B -m unittest discover -s scripts -p test_selection_export_https_contract.py -v
```

These six tests validate reports only. Actual HTTPS execution remains pending. No build, fixture run, native acceptance,
Codacy coverage, commit, push or deployment is implied.

## Profile regression evidence

The shared lifecycle now has an exclusive typed `selection_export_mode` profile.
It requires selection artifacts and the existing dates/location/full-v3 closure,
sets the selection backend flag explicitly, and leaves all import flags false.
The proxy adds only a separately opted-in GET selection route; query validation
remains the backend responsibility. Existing proxy profiles do not enable it.

Three new Python profile tests verify exclusivity, artifact closure and mocked
owned lifecycle flags. The HTTPS-pattern Python suite passes 220 tests; the
proxy Node suite passes 36 tests, including two selection cases. These runs use
mocks, not PostgreSQL, backend, TLS keys or actual HTTPS. No resources were started.

## Driver and wrapper evidence

`scripts/selection-export-https-fixture.py` invokes only the fixed Dart driver,
with marker-bound loopback endpoint and an explicit Python executable. It rejects
partial or incorrectly typed reports; only allowlisted failure stages are saved.
The driver derives each successful check from actual assertions and closes its
clients in `finally`. It does not accept a native-save result.

After adding the wrapper, 226 HTTPS-pattern Python tests pass. The standalone
Dart HTTP-validator test passes and Flutter analyzer reports no issues. The
initial formatting invocation failed on SDK telemetry permissions after formatting
the driver; the approved SDK/cache invocation subsequently completed successfully.
No real HTTP/HTTPS request, database, TLS key read or build occurred in these tests.

A later execution requires a separately approved backend candidate build and one
synthetic HTTPS fixture using existing TLS/image prerequisites. Source tests do
not prove runtime auth, routing or data acceptance. Codacy empty-result responses
are not analyzer coverage and are not a PASS.

The additional preflight regression removes every required profile artifact in
turn and asserts refusal before sockets, subprocesses, TLS byte reads or local
resource directories. The wrapper diagnostic stages now match the selection
Dart driver, rather than carrying unrelated legacy export stages.

## Separately approved execution

One backend candidate build and one synthetic HTTPS execution completed without
retry. The real Dart driver passed the exact thirteen-check report validator;
the wrapper returned completed. Independent Docker inspection confirmed the
owned container stopped, matching ownership labels and loopback-only bindings;
the volume and evidence are retained. All 47 selected source hashes matched the
pre-run manifest, and all reported runtime artifact hashes matched afterward.

Evidence: `.local/asset-client-7b27c7ee40afedf1fe54076f69c971fd/result.json`
and `.local/selection-export-review/https-acceptance.json`. The wrapper validated
but did not persist the raw driver report; the retained completion report and
fixed source hashes establish which report contract was enforced. Earlier
preparation-only statements describe the offline stage, not this later run.

Native saving, Codacy analyzer coverage, commit, push and deployment remain
unverified or unapproved. No regular backend/database was targeted.

## Native launcher source preparation

The existing native runner accepts an exclusive `--selection-export-mode`.
Candidate verification requires the exact endpoint, hashed deployment inventory
and four build defines: selection export, full-v3 export, dates and location.
Import flags or missing defines refuse before launch. The existing marker-bound
v3 seed supplies one dated, located synthetic asset; no operator data is read.

The handoff asks for applied Search/status, Prepare with one matching record,
Save to a new file, Cancel retaining the prepared result and Back retaining
inventory filters. It identifies the file as a selection, not an import/backup.
A process opening or exiting never counts as manual acceptance.

Two new guarded native contracts pass; all 228 HTTPS-pattern offline tests pass.
The first new handoff test lacked its required candidate metadata and refused;
adding the correct synthetic manifest fixed that test, not the production guard.
No Windows build, native launch, new fixture or security-policy change occurred.
A separate approval is required for build and a bounded native fixture session.
