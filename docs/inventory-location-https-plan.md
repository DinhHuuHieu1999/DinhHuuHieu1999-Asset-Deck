---
title: "Inventory location HTTPS acceptance plan"
description: "Real Dart transport acceptance against an isolated synthetic backend."
document_type: "plan"
status: "draft"
audience: ["contributors", "operators"]
---

# Location HTTPS acceptance

Repository acceptance passed. The next boundary is the real Dart client through
TLS, authentication and CSRF to the optional backend routes. No HTTPS execution
or candidate build is authorized by this document.

## Source implementation

Reuse `scripts/client-https-fixture.py` and its owned lifecycle/proxy. Add one
fixed location profile, wrapper, Dart driver and offline contract tests.

- Validate the profile as an explicit boolean; reject incompatible import modes.
- Fixed prerequisites include migration 005 and all location source/build files.
- Apply only 001/002/004/005 inside the newly provisioned synthetic database.
- Set location and dates flags explicitly for this profile. Existing profiles
  must explicitly disable location rather than inherit an operator environment.
- Require the profile-specific acceptance driver before creating resources.
- Hash the fixed driver/source/artifacts before and after acceptance.
- Preserve existing image, port, TLS, deadline, ownership and stop guards.
- No arbitrary environment overrides, SQL paths, suite paths or command hooks.

## Real-client scenarios

1. Validate the fixture marker using default TLS verification before registration.
2. Register two synthetic owners; reject anonymous read/write and missing CSRF.
3. Create an asset, read unknown location and replace it with a literal label.
4. Verify other-owner read/update cannot access it; no extra asset is created.
5. Verify stale shared versions fail after base/date/location updates.
6. Verify unrelated fields/dates remain unchanged and clearing is explicit.
7. Combine search/status/category/exact/unknown location and warranty predicates;
   use enough matches to verify the second page and fixed warranty reference.
8. Verify existing export schemas remain unchanged and omit location labels.
9. Sign out and refuse further client operations; emit only a fixed result shape.

Report stage names only on failure, never credentials, cookies or response bodies.
Partial or malformed output and source drift must fail acceptance.

## Execution boundary

After source/offline review, request a separate backend candidate build and one
HTTPS fixture invocation. Use an existing PostgreSQL image, new synthetic
container/volume and three free loopback ports; reference the existing localhost
certificate without changing trust/firewall. No retry, regular backend changes,
Windows build, provider call, commit or deployment. Verify ownership before stop
and retain evidence/data. Native UI remains a separate acceptance step.

## Offline implementation checkpoint

The fixed profile/wrapper, real Dart driver and proxy route opt-in are implemented.
Offline checks cover source prerequisites, profile incompatibility, inherited flag
isolation, cleanup, exact result types and source drift. Three Dart argument tests
refuse regular endpoints, malformed markers and missing executable paths before
network/process work. Proxy tests keep location separate from import capability.

One separately approved backend build and HTTPS invocation completed. The real
Dart client passed the fixed two-owner, 53-asset scenario, including literal
location/warranty paging and both export versions. Source hashes were unchanged;
cleanup reported stopped. Synthetic resources and evidence were retained.
Native UI, restart/restore and regular-backend rollout remain unverified.
