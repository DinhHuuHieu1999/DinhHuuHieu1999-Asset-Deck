---
title: "Inventory location PostgreSQL acceptance"
description: "Opt-in isolated repository checks for manual locations."
document_type: "plan"
status: "draft"
audience: ["contributors", "operators"]
---

# Location repository fixture

Execution requires separate operator approval. One approved isolated run completed
all four scenarios with no skips or failures; ownership-checked cleanup reported
the synthetic container stopped. The volume and local report were retained.
This is repository acceptance only, not HTTPS or Windows acceptance.

## Boundaries

- Existing immutable PostgreSQL image only; no pull or dependency installation.
- New synthetic database, labeled container and volume; no real-data mount.
- One ephemeral host port bound only to `127.0.0.1`.
- Shared 120-second deadline; one fixed Jest suite, no assertion retry.
- Identity/readiness checks before migrations 001/002/004/005.
- Verify ownership before stopping; retain stopped container, volume and report.
- No backend, HTTPS, Windows build, regular database, commit or deployment.

## Fixed scenarios

1. Owner isolation; location edits preserve base fields and purchase/warranty dates.
2. Concurrent location/date edits share one optimistic version; stale edits fail.
3. Exact case-sensitive literal location, unknown, owner, search, category, status
   and warranty predicates apply before paging; 51 matches span two pages.
4. Explicit clear, legacy-edit preservation and SQL constraint rejection.

The suite defaults to skipped. Skips do not count as acceptance. The Python
runner refuses missing source/tools or missing opt-in before creating resources.
Offline lifecycle tests replace every runtime command with a synthetic dispatcher;
they verify the fixed migration order, suite, environment and cleanup.

## Authorized invocation template

After approval, use an already verified local image ID, not a mutable tag:

```powershell
python -B scripts/location-postgres-fixture.py --execute-synthetic --image sha256:<existing-image-id>
```

This repository fixture does not certify HTTP authentication, TLS, native UI,
export portability or backup/restore behavior.
