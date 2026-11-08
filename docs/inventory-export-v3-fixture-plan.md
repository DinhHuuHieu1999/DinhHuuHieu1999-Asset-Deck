---
title: "Inventory export v3 repository fixture"
description: "Opt-in owner-scoped snapshot acceptance with manual locations."
document_type: "plan"
status: "draft"
audience: ["contributors", "operators"]
---

# Inventory export v3 repository fixture

Harness execution requires separate operator approval. One approved isolated
run passed all four scenarios with no skips; cleanup reported owned resources
stopped. Future executions still require approval. HTTPS and native acceptance
remain pending.

## Scope

Reuse the bounded repository lifecycle, with a fixed v3 suite and identity.
Require an existing immutable PostgreSQL image; never pull or build. Create a new
synthetic container, volume and database, with one dynamically allocated port
bound only to `127.0.0.1`. Apply migrations 001, 002, 004 and 005 only inside that
fixture. There is no backend, HTTPS, native client or model invocation.

The overall execution deadline is 120 seconds. Run Jest once, without retry;
all four scenarios must pass, with no skips or runtime errors. Verify the
fixture ownership label before stopping it. Retain the stopped container, volume
and evidence; do not delete or touch regular databases.

## Fixed scenarios

1. Empty inventory, nullable location/dates, extreme calendar dates and literal
   location `Room %_1`; verify the exact payload checksum.
2. Export all 51 owner records, exclude a second owner's private record, and
   compare database rows before/after to prove the export did not write.
3. Refuse 501 records rather than returning a truncated complete export.
4. Observe a blocked snapshot statement through `pg_stat_activity`, commit an
   edit, then verify base fields, shared version, dates and location all come
   from the same pre-edit snapshot; the next export sees the committed edit.

## Commands

Offline lifecycle contracts (mocked commands, no Docker/DB):

```powershell
python -B -m unittest discover -s scripts -p test_export_v3_postgres_fixture.py -v
```

After separate approval, supply an already verified local image digest:

```powershell
python -B scripts/export-v3-postgres-fixture.py --execute-synthetic --image sha256:<existing-image-digest>
```

Missing source/tool/image, unexpected binding/identity, incomplete Jest output
or cleanup failure refuses acceptance. Default backend tests skip the live suite
without its exact fixture opt-in. Offline success does not certify SQL behavior,
HTTPS auth, Windows saving or deployment.
