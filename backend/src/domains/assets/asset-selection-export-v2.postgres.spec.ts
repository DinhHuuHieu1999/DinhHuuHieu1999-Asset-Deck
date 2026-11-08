import { AssetSelectionExportV2Repository } from './asset-selection-export-v2.repository';
import { createHash, randomBytes } from 'node:crypto';
import {
  buildAssetSelectionExportV2,
  type AssetSelectionScopeV2,
} from './asset-selection-export-v2';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_SELECTION_V2_FIXTURE_OPT_IN === 'isolated-selection-v2'
    ? describe
    : describe.skip;
suite('isolated selection export repository acceptance', () => {
  let pool: Pool;
  let repository: AssetsRepository;
  let owner: string;
  let other: string;
  let dates: AssetDatesRepository;
  let exporter: AssetSelectionExportV2Repository;
  const scope: AssetSelectionScopeV2 = {
    q: '',
    status: '',
    category: '',
    locationMode: 'all',
    location: null,
    sort: 'updated_desc',
    warranty: null,
    check: { mode: 'all' },
  };
  const input = {
    name: 'Synthetic router',
    category: 'network',
    serial: '%_1',
    status: 'stored' as const,
    notes: 'Synthetic only',
  };
  beforeAll(async () => {
    const raw = process.env.ASSET_SELECTION_V2_FIXTURE_URL;
    const marker = process.env.ASSET_SELECTION_V2_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_selection_v2_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
      !url.port ||
      ['5432', '5433'].includes(url.port) ||
      url.search ||
      url.hash
    )
      throw new Error('Refusing non-fixture target');
    pool = new Pool({
      connectionString: raw,
      max: 4,
      connectionTimeoutMillis: 5000,
      statement_timeout: 5000,
      application_name: 'asset-selection-export-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_selection_v2_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetsRepository({ pool } as PostgresDatabase);
    await repository.ready();
    dates = new AssetDatesRepository({ pool } as PostgresDatabase);
    await dates.ready();
    exporter = new AssetSelectionExportV2Repository({
      pool,
    } as PostgresDatabase);
    await exporter.ready();
  }, 30000);
  beforeEach(async () => {
    owner = randomBytes(12).toString('hex');
    other = randomBytes(12).toString('hex');
    for (const id of [owner, other]) {
      await pool.query(
        `INSERT INTO auth.accounts(id,email,username,name,password_hash)
        VALUES($1,$2,$3,'Synthetic category owner','not-a-login-hash')`,
        [id, `${id}@example.invalid`, `category_${id.slice(0, 16)}`],
      );
    }
  }, 30000);
  afterAll(async () => {
    if (pool) await pool.end();
  });

  it('exports empty and preserves public dates/location with a real checksum', async () => {
    expect(
      JSON.parse(
        buildAssetSelectionExportV2(
          await exporter.exportSnapshot(owner, scope),
          scope,
        ).payload,
      ).recordCount,
    ).toBe(0);
    const row = await repository.create(owner, input);
    await dates.update(owner, row.id, {
      version: 1,
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: '2027-02-28',
    });
    await pool.query('UPDATE assets.assets SET location=$1 WHERE id=$2', [
      'Room %_1',
      row.id,
    ]);
    const envelope = buildAssetSelectionExportV2(
      await exporter.exportSnapshot(owner, scope),
      scope,
    );
    expect(envelope.format).toBe('asset-desk-inventory-selection');
    const payload = JSON.parse(envelope.payload);
    expect(payload.complete).toBeUndefined();
    expect(payload.records[0]).toMatchObject({
      id: row.id,
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: '2027-02-28',
      location: 'Room %_1',
    });
    expect(envelope.sha256).toBe(
      createHash('sha256').update(envelope.payload, 'utf8').digest('hex'),
    );
  });

  it('exports all 51 owner matches without writing or leaking the second owner', async () => {
    for (let i = 0; i < 51; i++)
      await repository.create(owner, { ...input, name: `Synthetic ${i}` });
    const hidden = await repository.create(other, input);
    const before = await pool.query(
      'SELECT json_agg(a ORDER BY id)::text AS data FROM assets.assets a',
    );
    const snapshot = await exporter.exportSnapshot(owner, scope);
    expect(snapshot.records).toHaveLength(51);
    expect(snapshot.records.some((row) => row.id === hidden.id)).toBe(false);
    expect(
      (await exporter.exportSnapshot(other, scope)).records.map(
        (row) => row.id,
      ),
    ).toEqual([hidden.id]);
    const payload = buildAssetSelectionExportV2(snapshot, scope).payload;
    expect(payload).not.toContain('owner_id');
    expect(
      (
        await pool.query(
          'SELECT json_agg(a ORDER BY id)::text AS data FROM assets.assets a',
        )
      ).rows,
    ).toEqual(before.rows);
  });

  it('accepts 500 matches and refuses the 501 sentinel rather than truncating', async () => {
    await pool.query(
      `INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes)
      SELECT md5($1::text || ':' || n::text)::uuid,$1,'Synthetic '||n,'fixture','','stored','' FROM generate_series(1,500) n`,
      [owner],
    );
    expect(
      JSON.parse(
        buildAssetSelectionExportV2(
          await exporter.exportSnapshot(owner, scope),
          scope,
        ).payload,
      ).recordCount,
    ).toBe(500);
    await pool.query('UPDATE assets.assets SET notes=$1 WHERE owner_id=$2', [
      '\u754c'.repeat(2000),
      owner,
    ]);
    const oversized = await exporter.exportSnapshot(owner, scope);
    expect(() => buildAssetSelectionExportV2(oversized, scope)).toThrow(
      '1 MiB',
    );
    await pool.query("UPDATE assets.assets SET notes='' WHERE owner_id=$1", [
      owner,
    ]);
    await repository.create(owner, input);
    const snapshot = await exporter.exportSnapshot(owner, scope);
    expect(snapshot.records).toHaveLength(501);
    expect(() => buildAssetSelectionExportV2(snapshot, scope)).toThrow(
      'no partial export',
    );
  });

  it('evaluates literal case-insensitive search and every filter before the limit', async () => {
    await pool.query(
      `INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes)
      SELECT md5($1::text || ':' || n::text)::uuid,$1,'Distractor '||n,'fixture','','stored','' FROM generate_series(1,501) n`,
      [owner],
    );
    const target = await repository.create(owner, {
      ...input,
      name: 'Literal %_ MATCH',
      category: 'fixture',
    });
    await pool.query(
      "UPDATE assets.assets SET location='Room %_1',warranty_expires_on='2026-11-28' WHERE id=$1",
      [target.id],
    );
    await repository.create(owner, {
      ...input,
      name: 'Literal XX MATCH',
      category: 'fixture',
    });
    const selected: AssetSelectionScopeV2 = {
      ...scope,
      q: '%_ match',
      status: 'stored',
      category: 'fixture',
      locationMode: 'exact',
      location: 'Room %_1',
      warranty: {
        filter: 'expiring_soon',
        asOf: '2026-10-29',
        through: '2026-11-28',
      },
    };
    expect(
      (await exporter.exportSnapshot(owner, selected)).records.map(
        (row) => row.id,
      ),
    ).toEqual([target.id]);
    expect(
      (await exporter.exportSnapshot(owner, { ...selected, status: 'repair' }))
        .records,
    ).toEqual([]);
    expect(
      (
        await exporter.exportSnapshot(owner, {
          ...selected,
          category: 'Fixture',
        })
      ).records,
    ).toEqual([]);
  });

  it('unknown location and expired boundary exclude dated-today and unknown warranty', async () => {
    const expired = await repository.create(owner, input);
    const today = await repository.create(owner, input);
    await repository.create(owner, input);
    await pool.query(
      "UPDATE assets.assets SET warranty_expires_on='2026-10-28' WHERE id=$1",
      [expired.id],
    );
    await pool.query(
      "UPDATE assets.assets SET warranty_expires_on='2026-10-29' WHERE id=$1",
      [today.id],
    );
    const selected: AssetSelectionScopeV2 = {
      ...scope,
      locationMode: 'unknown',
      warranty: {
        filter: 'expired',
        asOf: '2026-10-29',
        through: '2026-11-28',
      },
    };
    expect(
      (await exporter.exportSnapshot(owner, selected)).records.map(
        (row) => row.id,
      ),
    ).toEqual([expired.id]);
    await pool.query("UPDATE assets.assets SET location='Known' WHERE id=$1", [
      expired.id,
    ]);
    expect((await exporter.exportSnapshot(owner, selected)).records).toEqual(
      [],
    );
  });

  it('uses deterministic ID ties in both sort modes', async () => {
    const ids = [];
    for (let i = 0; i < 3; i++)
      ids.push((await repository.create(owner, { ...input, name: 'Same' })).id);
    await pool.query(
      "UPDATE assets.assets SET updated_at='2026-10-29T00:00:00Z' WHERE owner_id=$1",
      [owner],
    );
    expect(
      (
        await exporter.exportSnapshot(owner, { ...scope, sort: 'name_asc' })
      ).records.map((row) => row.id),
    ).toEqual([...ids].sort());
    expect(
      (await exporter.exportSnapshot(owner, scope)).records.map(
        (row) => row.id,
      ),
    ).toEqual([...ids].sort().reverse());
  });

  it('keeps base fields, shared version and dates in one snapshot during a committed edit', async () => {
    const row = await repository.create(owner, {
      ...input,
      name: 'Before snapshot',
    });
    await dates.update(owner, row.id, {
      version: 1,
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: null,
    });
    const lock = await pool.connect();
    const key = 73498261;
    await lock.query('SELECT pg_advisory_lock($1)', [key]);
    const blocked = new AssetSelectionExportV2Repository({
      pool: {
        query: (sql: string, values: unknown[]) =>
          pool.query(
            `WITH barrier AS MATERIALIZED (SELECT pg_advisory_xact_lock(${key})) ` +
              sql +
              ' FROM barrier',
            values,
          ),
      },
    } as unknown as PostgresDatabase);
    const priorScope: AssetSelectionScopeV2 = {
      ...scope,
      q: 'Before snapshot',
    };
    const pending = blocked.exportSnapshot(owner, priorScope);
    // Observe the actual blocked statement, not an arbitrary timing sleep.
    void pending.catch(() => undefined);
    try {
      const until = Date.now() + 3000;
      while (true) {
        const waiting =
          await pool.query(`SELECT count(*)::int AS count FROM pg_stat_activity
          WHERE datname=current_database() AND wait_event_type='Lock'
          AND query LIKE '%pg_advisory_xact_lock(73498261)%'`);
        if (waiting.rows[0].count === 1) break;
        if (Date.now() >= until)
          throw new Error('Snapshot barrier not observed');
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      await lock.query(
        `UPDATE assets.assets SET name='After snapshot',location='After room',purchased_on='2025-01-01',
        warranty_expires_on='2027-01-01',last_checked_on='2024-03-02',version=version+1,updated_at=clock_timestamp()
        WHERE id=$1 AND owner_id=$2`,
        [row.id, owner],
      );
      await lock.query('SELECT pg_advisory_unlock($1)', [key]);
      const snapshot = await pending;
      expect(snapshot.records[0]).toMatchObject({
        name: 'Before snapshot',
        lastCheckedDate: null,
        location: null,
        version: 2,
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: null,
      });
      expect(
        (await exporter.exportSnapshot(owner, priorScope)).records,
      ).toEqual([]);
      expect(
        (await exporter.exportSnapshot(owner, scope)).records[0],
      ).toMatchObject({
        name: 'After snapshot',
        lastCheckedDate: '2024-03-02',
        location: 'After room',
        version: 3,
        purchasedOn: '2025-01-01',
        warrantyExpiresOn: '2027-01-01',
      });
    } finally {
      await lock.query('SELECT pg_advisory_unlock($1)', [key]);
      lock.release();
      await pending.catch(() => undefined);
    }
  }, 15000);
  it('checks strict and inclusive cutoff boundaries without including unknown dates', async () => {
    const ids: string[] = [];
    for (const date of [null, '2024-02-28', '2024-02-29', '2024-03-01']) {
      const row = await repository.create(owner, input);
      ids.push(row.id);
      await pool.query(
        'UPDATE assets.assets SET last_checked_on=$1 WHERE id=$2',
        [date, row.id],
      );
    }
    for (const [check, expected] of [
      [{ mode: 'unknown' }, [ids[0]]],
      [{ mode: 'before', cutoff: '2024-02-29' }, [ids[1]]],
      [{ mode: 'on_or_after', cutoff: '2024-02-29' }, [ids[2], ids[3]]],
    ] as const) {
      const selected = { ...scope, check } as AssetSelectionScopeV2;
      const snapshot = await exporter.exportSnapshot(owner, selected);
      expect(snapshot.records.map((record) => record.id).sort()).toEqual(
        [...expected].sort(),
      );
      expect(
        JSON.parse(buildAssetSelectionExportV2(snapshot, selected).payload)
          .filters.check,
      ).toEqual(check);
    }
  });
});
