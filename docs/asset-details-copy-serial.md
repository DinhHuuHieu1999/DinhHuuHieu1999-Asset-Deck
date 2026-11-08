# Copy asset serial

Status: source/tests and synthetic Windows clipboard/keyboard acceptance verified;
commit review pending.

Asset details offers an explicit Copy serial action using Flutter's platform
clipboard. It copies the exact displayed snapshot value, including literal `%`
and `_`; it does not query or write the backend. Empty serials disable the action.
Repeated actions replace the short feedback instead of queuing success messages.
Clipboard failures show a generic retry message without including the serial.
Busy/editing states disable copy; session invalidation hides private actions and
late completion cannot show feedback for a replaced snapshot.

The system clipboard is not private application storage. Clipboard history,
synchronization and other applications may retain copied serials. No automatic
clipboard reading, clearing or retry is performed.

Focused widget tests cover explicit exact copy, empty values, platform failure,
duplicate taps and late completion after session invalidation.
The operator verified exact native clipboard output, success feedback and keyboard
activation on the synthetic Windows candidate. Screen-reader acceptance remains
unverified. Flutter regression passed 901 tests with one opt-in test skipped;
analyzer reported no issues.
A Windows release candidate was built offline with `--no-pub`; a separate
synthetic HTTPS session has ended and its owned resources were stopped. No migration,
new dependency or deployment to the regular backend is included.

Codacy MCP returned empty results for the four candidate files. Analyzer coverage
was not established; this is not a Codacy or security PASS. No coverage exception
or commit approval is implied by the functional acceptance.
