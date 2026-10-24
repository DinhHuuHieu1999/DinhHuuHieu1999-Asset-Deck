# Client HTTPS acceptance plan

Status: source/offline preparation and the separately approved HTTPS client run
completed. Further runs require separate approval.

## Finding and selected approach

The Asset Desk backend entrypoint binds HTTP to `127.0.0.1`; proxy trust is false.
The Flutter client requires HTTPS by default and release ignores the debug-only
loopback HTTP allowance. Mock/loopback HTTP tests do not prove these work together.

Use a test-only HTTPS reverse proxy forwarding to a separately owned loopback
backend candidate. Keep TLS termination out of product code for this acceptance
step, consistent with the base deployment boundary. Do not copy ToolDeck's
multi-listener/LAN implementation or change backend proxy trust.
No new dependency or externally hosted service is needed.

The installed backend dependencies, `backend/dist/main.js` and Flutter package
configuration exist on this checkout. Earlier one-off fixture harnesses/reports
mentioned in session history are not present under this checkout's `.local`.
Do not depend on those missing files or claim they were reverified here.
Prepare explicit fixture source and its offline checks before requesting execution.

## Source preparation (does not run the fixture)

- A test-only proxy with fixed loopback upstream; never accept an upstream from
  an HTTP request. Reject unsupported paths/methods and oversized bodies.
- Forward bearer, CSRF cookie/header and request timestamp without logging values.
  Bound body reads, upstream response size and request/connection deadlines.
- Return only safe errors. Strip hop-by-hop headers and never follow redirects.
- Expose a random fixture-identity marker for read-only preflight. The client driver
  must verify the exact marker before account registration or other writes.
  This prevents accidental targeting, not malicious same-account code access.
- A Dart driver imports the actual `AssetApi`, uses default certificate validation
  and generates all synthetic account passwords in memory. No real account or env.
- The opt-in orchestrator owns the candidate/backend/proxy process handles and
  labelled database resources. No service discovery or process-name killing.
- Offline tests check configuration, bounds, fixed routing, safe reporting and
  refusal before side effects when prerequisites or ownership are missing.

## One proposed live run (requires separate approval)

1. Build the backend candidate once with installed dependencies; record hashes.
   No install, network download or lifecycle hook.
2. Verify an existing PostgreSQL image without pulling and an existing localhost
   certificate/key only at explicitly approved paths. Never copy/log the key.
3. Create one new labelled database/container/volume and apply only migrations
   `001-auth-accounts.sql` and `002-assets.sql`. Publish only to loopback.
4. Start the owned backend on a distinct loopback port with synthetic database,
   JWT/CSRF secrets and `CSRF_COOKIE_SECURE=true` in its child environment only.
   Fixture throttling may be raised explicitly to accommodate bounded seed calls.
5. Start the owned TLS proxy on a separate loopback port. Verify certificate
   validity, hostname and trust using the Dart default TLS context. Stop on failure;
   never install trust, disable validation or use the debug HTTP allowance.
6. Verify the fixture marker, then run the actual Dart client: register two owners;
   create 51 assets; check literal `%`/`_`, status filtering before pagination,
   complete two-page traversal, foreign-owner isolation, optimistic edit/conflict,
   sign-out and login from a fresh client instance. No automatic retry.
7. Record safe outcomes/counts and source hashes, not credentials or full responses.
   A fresh client login is not a backend restart/restore test.
8. In `finally`, stop only verified owned processes/container, confirm listeners
   are gone and retain the synthetic volume/evidence. No deletion is implicit.

Use a bounded overall deadline and a separate bounded client-driver deadline.
No retry after a failed attempt; inspect evidence and request a new run if needed.

## Limits and rollback

No regular ToolDeck/Asset Desk runtime, database, account, listener, env file,
trust store or firewall changes. No model/provider/upload or Windows app launch.
Stop on missing image, invalid TLS, occupied ports or failed ownership checks.
Rollback is stopping the isolated resources; retain schema/data for inspection.
Passing this fixture does not prove Windows runner packaging, SAC compatibility,
manual accessibility, clean-checkout reproduction or deployment readiness.

## Source preparation and offline verification

Source preparation is approved; executing the fixture still requires separate approval.
The opt-in runner is `scripts/client-https-fixture.py`. It requires an immutable
existing image ID, explicit absolute TLS paths and three distinct non-default
loopback ports. It never builds, installs dependencies, pulls an image or changes
trust. Build and candidate review must happen separately before an approved run.
On Windows the runner requires the SDK `dart.exe`, not the Flutter batch wrapper,
so its timeout owns the actual VM process. It uses direct VM script mode
(`--disable-dart-dev`) without package resolution or downloads.

- `scripts/client-https-proxy.mjs`: fixed upstream, bounded requests/responses and
  deadline, exact fixture marker, hop-header removal and redirect refusal.
- `scripts/client-https-backend.cjs`: fixture-only preload emits readiness only
  after the exact HTTP server binds loopback. The runner checks child PID, port
  and identity before starting the proxy or driver; TCP reachability alone is
  not accepted as backend ownership.
- `scripts/client-https-proxy-cli.mjs`: explicit synthetic opt-in, TLS loading only
  on execution, loopback binding and safe errors.
- `flutter/tool/client_https_acceptance.dart`: actual `AssetApi`, default TLS,
  mandatory marker before writes, two synthetic owners and 51-record scenario.
- `scripts/test_client_https_fixture.py`: injected fake runtime, filesystem
  fixtures, and guards rejecting real subprocess/network calls.
- `scripts/client-https-proxy.test.mjs`: stream-only transport simulation; no TLS
  file, listener or backend is used.
- `flutter/test/client_https_acceptance_test.dart`: target/marker refusal checks.

Run the offline contracts from the repository root:

```powershell
python -B scripts/test_client_https_fixture.py -v
node --test scripts/client-https-proxy.test.mjs
```

From `flutter/`, using the installed SDK and package cache:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

The runner uses a fresh ignored working directory so the backend env loader cannot
read the application's local env files. It supplies synthetic database/JWT/CSRF
values only to child environments and never reports subprocess output. Cleanup
uses exact process handles and a matching container label, retains the volume and
writes a safe result. Cleanup failure makes the overall result failed, even when
the client scenario completed. The marker prevents accidental targeting only.

The first approved live attempt stopped before backend readiness. Its retained
PostgreSQL log contains a missing `fixture` database during initialization; the
old Unix-socket `pg_isready` check could accept the temporary initialization server.
The source now requires a TCP SQL identity check before migrations. This correction
passed 11 offline runner tests and the separately approved new live fixture.
The failed fixture was not restarted or retried.

No Windows build has occurred in this phase. Offline tests do not prove TLS trust, Docker/image
compatibility, actual Dart/backend interoperability or cleanup of real processes.

## Verified HTTPS client result (2026-10-25)

The new fixture `575a60129ee87add78999cdf776a7737` completed using the unchanged
backend candidate (`main.js` SHA-256 begins `e46180964f604c20`). The actual Dart
`AssetApi` used default certificate/hostname validation and secure CSRF cookies.
The driver required the matching synthetic marker before registration or writes.

Verified: two owners; 51 assets; literal `%_` search; status filtering before
pagination; unique 50+1 traversal; foreign-owner edit rejection; update/version
conflict; sign-out and login through a fresh client. All checks were explicit,
not disabled-language assertions. No write was automatically retried.

The retained local `result.json` records completed status, source hashes and
`cleanup: stopped`; the container was separately confirmed exited. The synthetic
volume remains retained. No regular backend/account/database, trust or firewall
was changed. No new dependency, image pull, rebuild or Windows app launch occurred
in this new run. The earlier approved backend build was reused.

This does not prove native UI, Windows packaging/SAC behavior, browser cookie
behavior, manual accessibility, clean-checkout deployment or HTTPS restart/restore.
The earlier recovery fixture is separate evidence, not a substitute for these gates.
