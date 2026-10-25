# Asset Desk Flutter client source

Source for authenticated personal equipment inventory. No regular deployment or
native acceptance is implied. There is a `main.dart` entry point and Windows runner source rendered from the
installed SDK template. A Windows release candidate built successfully after
offline plugin metadata generation; the functional operator checks below passed on a synthetic fixture.

Implemented: login/register, bounded native JSON transport, CSRF cookie/header,
in-memory bearer session, inventory search/status/pagination and manual create/edit.
Sign-out and HTTP 401 replace the entire private navigator, including draft forms.
Late responses cannot restore an older account or private list. No credentials
or equipment records are written to disk by the client.

Failed writes are never retried automatically. Conflicts and unknown write outcomes
preserve the draft and block blind resubmission; return and refresh before another
write. Unknown registration outcomes direct the user to sign in before trying to
register again. Sign-out clears unsaved drafts and does not revoke the server JWT.

## Configuration boundary

| Compile-time setting          | Behavior                                                                 |
| ----------------------------- | ------------------------------------------------------------------------ |
| `ASSET_DESK_API_URL`          | Explicit endpoint ending in `/api/v1`; HTTPS required by default         |
| `ASSET_DESK_ALLOW_LOCAL_HTTP` | Debug-only opt-in for explicit loopback HTTP; ignored in profile/release |

No automatic endpoint discovery, TLS bypass or remembered password is provided.
The client sends `x-request-timestamp` and does not follow HTTP redirects.
Response JSON is bounded to 1 MiB. Password-reset delivery is not configured.
Do not connect this source to a regular backend before isolated acceptance.

## Verification

```powershell
flutter pub get --offline --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Analyzer and 86 unit/widget/harness tests pass using the installed SDK/cache. Transport
tests bind an ephemeral loopback HTTP server in-process with synthetic responses;
they do not start the product backend or database and do not certify HTTPS.
Widget tests cover draft keep/discard, stale results, paging, account/session
invalidation and unknown write outcomes. No external production dependency was added.

Synthetic baseline and inventory/auth renders were inspected locally at
390/768/1440 pixels with text scale set to 200%; Material AppBar titles retain
Flutter's built-in scaling clamp. Visible tap-target and label checks pass.
These checks do not replace native or manual keyboard/screen-reader acceptance.
Optional captures use `ASSET_DESK_UI_CAPTURE_FONT`, `ASSET_DESK_UI_CAPTURE_ICONS`
and `ASSET_DESK_UI_CAPTURE_DIR`, referring only to local fonts and ignored output.
The baseline test writes under the product's ignored `.local/flutter-ui`.

A separately approved HTTPS fixture passed using the actual `AssetApi`, default
TLS validation and secure CSRF cookies: two owners, 51 assets, literal search,
status/paging, owner isolation, edit/conflict and fresh-client login. This was a
Dart CLI driver, not the native Flutter UI. The fixture was stopped and retained.
See the [HTTPS acceptance scope](../docs/client-https-acceptance-plan.md).

A local clone of commit `8e1430c` also passed offline pub resolution with the
lockfile enforced, analyzer and all 82 tests using the installed SDK/cache.
The clone remained Git-clean. Backend dependency installation needed separately
approved network metadata access; this was not an entirely offline bootstrap.

The candidate process opened on a separately approved synthetic HTTPS fixture.
The operator confirmed sign-in, literal search/status filtering, create/edit with
refresh, draft keep/discard and sign-out/sign-in persistence. These are manual
functional confirmations, not automated UI observations. The operator also confirmed Tab/Shift+Tab focus and Enter/Space activation.
Native text scaling, screen-reader and error/conflict interaction checks remain pending.
See the [native acceptance plan](../docs/windows-native-acceptance-plan.md).
Source analysis returning an empty result does not establish Dart/security coverage.
The Windows runner source is prepared but not yet committed. No fonts, screenshots,
credentials or generated builds are committed.

See [source provenance](../docs/flutter-source-provenance.json).
