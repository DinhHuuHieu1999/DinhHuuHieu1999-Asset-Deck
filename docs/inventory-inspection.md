# Local inventory JSON inspection

## Behavior and boundaries

Inspect is read-only and separate from export and any future import. The operator
explicitly selects one local Windows JSON file, between 2 bytes and 1 MiB. The
existing strict export v1 parser validates at most 500 assets. Malformed UTF-8,
a byte-order mark, duplicate keys, unsupported versions, incomplete records and
checksum mismatch fail before a preview is shown. A matching checksum does not
prove authenticity or ownership. Serial numbers and notes may be sensitive.

No backend call, database write, URL activation, credential persistence or import
is performed by inspection. Cancel retains the previous preview. A newly selected
file clears that preview before verification; an error must not misrepresent old
data as belonging to a new file. Session replacement disposes private previews,
including pending picker/digest results. Controls disable during selection.

The native reader opens existing local JSON read-only, checks disk type and size,
rejects known reparse parents and leaf reparse points, and returns bytes rather
than a private path. This is not a filesystem sandbox against same-account races.
Native selection does not validate JSON syntax; Dart performs that validation.

## Verified scope

- Complete Flutter suite: 159 passed, one opt-in test skipped; analyzer clean.
- Four byte-parser and seven mocked native-channel tests are included above.
- Ten page/navigation tests cover preview, Cancel, checksum/read failure, disabled
  controls, late picker/digest results, Back preserving filters without store
  reload/write, and real application sign-out clearing private routes.
- Pre-change inventory and post-change preview renders inspected at text 200%,
  widths 390 and 1440, without overflow. The capture font lacks some fixture
  Unicode glyphs; glyph fidelity and screen-reader behavior are not certified.
- Five static native contracts and three provenance tests pass.
- The isolated Windows release built using locked offline dependencies and
  `--no-pub`; 61 selected source files and all 11 packaged output hashes matched.
- The MSVC helper passed 29 assertions, including known SHA-256 vectors,
  no-overwrite export and bounded inspection reads. It retained synthetic files.
  The initial helper compilation failed on output-path quoting before execution;
  correcting that invocation succeeded without changing source or bypassing checks.

Static tests and the helper do not certify actual file-picker dialog behavior.
Codacy returned empty results without analyzer identity or coverage; this is not
a Codacy/security PASS. No coverage exception for this phase is implied.

## Native acceptance still blocked

The separately approved synthetic HTTPS session reached native launch but Windows
Code Integrity rejected the candidate under signing-level enforcement. Events
3077 and 3033 identified the candidate EXE. This does not establish a product
logic defect or certify the application as safe. The failed session was not
retried; cleanup reported stopped and its container was independently verified
exited with matching ownership. Existing security policy was not changed.

Actual Choose JSON, preview, Cancel and native accessibility acceptance remain
pending. No regular backend/database, trust/firewall or dependency was changed.
No commit, push, import or deployment is implied by these local results.
