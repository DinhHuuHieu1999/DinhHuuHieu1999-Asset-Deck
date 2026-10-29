# Selection export PostgreSQL acceptance

Status: one separately approved PostgreSQL fixture passed all seven scenarios.
The owned container is stopped and its volume/evidence retained.

## Boundaries

`scripts/selection-export-postgres-fixture.py` dispatches the fixed
`selection-export` profile of the existing repository lifecycle. It requires
`--execute-synthetic` and an already present immutable `sha256:` image ID.
No pull, dependency installation, backend build, HTTPS, native app or real data.

The runner creates one synthetic database/container/volume with an identity label,
one random port bound only to 127.0.0.1, and a database ownership marker. It applies
existing migrations 001, 002, 004 and 005 only in that database. Source/Jest/tool
preflight runs before output creation. The total execution deadline is 120 seconds;
there is no automatic fixture retry. Bounded database readiness polling is not a
fixture rerun. Cleanup has its existing separate 30-second budget, verifies
ownership before stopping, checks stopped state, and retains the container/volume
and ignored evidence. It never deletes them.

Default Jest execution skips all seven cases without constructing a database pool.
The opt-in suite also validates loopback URL, dedicated database prefix and marker
before seeding; it does not accept a normal backend connection string.

## Seven scenarios

1. Empty selection, public date/location preservation and exact payload checksum.
2. All 51 matches across a list-page boundary, two-owner isolation and no writes.
3. 500 accepted; 501 or a multibyte envelope above 1 MiB rejected without truncation.
4. Literal percent/underscore case-insensitive search combined with status,
   exact category, exact location and warranty, despite 501 unrelated rows.
5. Unknown location and expired warranty boundary; expiry today/unknown excluded.
6. Deterministic ID tie-breakers for name and recent-update order.
7. A real blocked statement snapshot retains pre-edit fields/filter membership
   while an independently committed edit becomes visible to the next export.

The snapshot barrier is observed through PostgreSQL lock state, not inferred from
an arbitrary sleep. A partial, skipped or malformed Jest summary is failure.
Offline lifecycle mocks prove orchestration only, not SQL semantics, confinement,
HTTPS or native acceptance. The real run is recorded below.

## Verified execution

One approved execution used the already present immutable PostgreSQL image,
without pull or retry. Jest reported 7 passed, 7 total, zero skipped/failed.
The runner reported completed/stopped; a separate Docker inspect confirmed
stopped state, matching ownership labels, loopback-only port configuration and
the retained volume. The 36-file source manifest remained unchanged through the
run. Local ignored evidence is under
`.local/asset-selection-export-c75949c9397d489c7814e9e950193a6d`; its acceptance
receipt is `.local/selection-export-review/postgres-acceptance.json`.

This proves the seven repository/serialization scenarios on that synthetic
PostgreSQL fixture only. It does not prove HTTP auth, HTTPS transport, native
saving, deployment, or Codacy coverage. No regular database was targeted.
