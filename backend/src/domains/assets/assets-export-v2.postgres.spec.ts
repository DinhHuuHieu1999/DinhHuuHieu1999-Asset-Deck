import { createHash, randomBytes } from 'node:crypto';
import { buildAssetExportV2 } from './asset-export-v2';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_EXPORT_V2_FIXTURE_OPT_IN === 'isolated-export-v2-v1'
    ? describe
    : describe.skip;
suite('isolated export v2 repository acceptance', () => {
  let pool: Pool;
  let repository: AssetsRepository;
  let owner: string;
  let other: string;
  let dates: AssetDatesRepository;
  const input = {
    name: 'Synthetic router',
    category: 'network',
    serial: '%_1',
    status: 'stored' as const,
    notes: 'Synthetic only',
  };
  beforeAll(async () => {
    const raw = process.env.ASSET_EXPORT_V2_FIXTURE_URL;
    const marker = process.env.ASSET_EXPORT_V2_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_export_v2_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-export-v2-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_export_v2_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetsRepository({ pool } as PostgresDatabase);
    await repository.ready();
    dates = new AssetDatesRepository({ pool } as PostgresDatabase);
    await dates.ready();
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

  it('exports empty and explicit nullable/extreme dates without timezone conversion', async () => {
    expect(
      buildAssetExportV2(await dates.exportSnapshot(owner)).schemaVersion,
    ).toBe(2);
    expect((await dates.exportSnapshot(owner)).records).toEqual([]);
    const row = await repository.create(owner, input);
    let snapshot = await dates.exportSnapshot(owner);
    expect(snapshot.records).toHaveLength(1);
    expect(snapshot.records[0]).toMatchObject({
      id: row.id,
      version: 1,
      purchasedOn: null,
      warrantyExpiresOn: null,
    });
    await dates.update(owner, row.id, {
      version: 1,
      purchasedOn: '0001-01-01',
      warrantyExpiresOn: '9999-12-31',
    });
    snapshot = await dates.exportSnapshot(owner);
    const envelope = buildAssetExportV2(snapshot);
    expect(JSON.parse(envelope.payload).records[0]).toMatchObject({
      id: row.id,
      version: 2,
      purchasedOn: '0001-01-01',
      warrantyExpiresOn: '9999-12-31',
    });
    expect(envelope.sha256).toBe(
      createHash('sha256').update(envelope.payload, 'utf8').digest('hex'),
    );
  });

  it('exports all 51 owned records, excludes the other owner and never writes', async () => {
    for (let i = 0; i < 51; i++)
      await repository.create(owner, { ...input, name: `Synthetic ${i}` });
    const hidden = await repository.create(other, {
      ...input,
      name: 'Other owner private',
    });
    const before = await pool.query(
      'SELECT json_agg(a ORDER BY id)::text AS data FROM assets.assets a',
    );
    const snapshot = await dates.exportSnapshot(owner);
    const envelope = buildAssetExportV2(snapshot);
    const decoded = JSON.parse(envelope.payload);
    expect(decoded.complete).toBe(true);
    expect(decoded.recordCount).toBe(51);
    expect(new Set(decoded.records.map((r: { id: string }) => r.id)).size).toBe(
      51,
    );
    expect(envelope.payload).not.toContain(hidden.id);
    expect(envelope.payload).not.toContain('owner_id');
    expect(envelope.payload).not.toContain('Other owner private');
    expect(
      (await dates.exportSnapshot(other)).records.map((r) => r.id),
    ).toEqual([hidden.id]);
    const after = await pool.query(
      'SELECT json_agg(a ORDER BY id)::text AS data FROM assets.assets a',
    );
    expect(after.rows).toEqual(before.rows);
  });

  it('refuses 501 records instead of returning a truncated success', async () => {
    await pool.query(
      `INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes)
      SELECT md5($1::text || ':' || n::text)::uuid,$1,'Synthetic '||n,'fixture','','stored','' FROM generate_series(1,501) n`,
      [owner],
    );
    const snapshot = await dates.exportSnapshot(owner);
    expect(snapshot.records).toHaveLength(501);
    expect(() => buildAssetExportV2(snapshot)).toThrow('no partial export');
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
    const blocked = new AssetDatesRepository({
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
    const pending = blocked.exportSnapshot(owner);
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
        `UPDATE assets.assets SET name='After snapshot',purchased_on='2025-01-01',
        warranty_expires_on='2027-01-01',version=version+1,updated_at=clock_timestamp()
        WHERE id=$1 AND owner_id=$2`,
        [row.id, owner],
      );
      await lock.query('SELECT pg_advisory_unlock($1)', [key]);
      const snapshot = await pending;
      expect(snapshot.records[0]).toMatchObject({
        name: 'Before snapshot',
        version: 2,
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: null,
      });
      expect((await dates.exportSnapshot(owner)).records[0]).toMatchObject({
        name: 'After snapshot',
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
});
