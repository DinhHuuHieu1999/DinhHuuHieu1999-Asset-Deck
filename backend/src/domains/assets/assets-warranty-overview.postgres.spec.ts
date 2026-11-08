import { randomBytes } from 'node:crypto';
import { assetWarrantyWindow } from './asset-warranty';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_WARRANTY_OVERVIEW_FIXTURE_OPT_IN ===
  'isolated-warranty-overview-v1'
    ? describe
    : describe.skip;
suite('isolated warranty overview repository acceptance', () => {
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
    const raw = process.env.ASSET_WARRANTY_OVERVIEW_FIXTURE_URL;
    const marker = process.env.ASSET_WARRANTY_OVERVIEW_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_warranty_overview_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-warranty-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_warranty_overview_fixture_identity',
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

  async function seed(
    end: string | null,
    account = owner,
    name = 'Synthetic router',
  ) {
    const row = await repository.create(account, { ...input, name });
    await dates.update(account, row.id, {
      version: 1,
      purchasedOn: null,
      warrantyExpiresOn: end,
    });
    return row.id;
  }
  function overview(asOf = '2026-10-27', account = owner) {
    return dates.warrantyOverview(
      account,
      assetWarrantyWindow('expired', asOf),
    );
  }
  it('returns complete zero buckets for an empty owner', async () => {
    expect(await overview()).toEqual({
      complete: true,
      asOf: '2026-10-27',
      through: '2026-11-26',
      total: 0,
      expired: 0,
      expiringSoon: 0,
      later: 0,
      unknown: 0,
    });
  });
  it('counts beyond one page across every status', async () => {
    for (let i = 0; i < 57; i++) await seed('2026-10-26');
    await pool.query(
      "WITH numbered AS (SELECT id,row_number() OVER (ORDER BY id) AS n FROM assets.assets WHERE owner_id=$1) UPDATE assets.assets a SET status=(ARRAY['in_use','stored','repair','retired'])[((numbered.n-1)%4+1)::int] FROM numbered WHERE a.id=numbered.id",
      [owner],
    );
    expect(await overview()).toMatchObject({ total: 57, expired: 57 });
  });
  it('partitions reference, horizon, day after and null exactly', async () => {
    for (const day of [
      '2026-10-26',
      '2026-10-27',
      '2026-11-26',
      '2026-11-27',
      null,
    ])
      await seed(day);
    expect(await overview()).toMatchObject({
      total: 5,
      expired: 1,
      expiringSoon: 2,
      later: 1,
      unknown: 1,
    });
  });
  it('isolates a second owner', async () => {
    await seed(null);
    await seed('2020-01-01', other);
    expect(await overview()).toMatchObject({
      total: 1,
      unknown: 1,
      expired: 0,
    });
    expect(await overview('2026-10-27', other)).toMatchObject({
      total: 1,
      expired: 1,
      unknown: 0,
    });
  });
  it('handles leap day and saturated year horizon', async () => {
    await seed('2024-02-29');
    await seed('9999-12-31');
    expect(await overview('2024-02-29')).toMatchObject({
      expiringSoon: 1,
      later: 1,
      through: '2024-03-30',
    });
    expect(await overview('9999-12-20')).toMatchObject({
      expired: 1,
      expiringSoon: 1,
      through: '9999-12-31',
    });
  });
  it('does not inherit the 200-category overview cap', async () => {
    for (let i = 0; i < 201; i++)
      await repository.create(owner, { ...input, category: 'category-' + i });
    expect(await overview()).toMatchObject({ total: 201, unknown: 201 });
  });
  it('returns a consistent partition while another transaction edits a date', async () => {
    const id = await seed('2026-10-26');
    const writer = await pool.connect();
    try {
      await writer.query('BEGIN');
      await writer.query(
        "UPDATE assets.assets SET warranty_expires_on='2026-12-01' WHERE owner_id=$1 AND id=$2",
        [owner, id],
      );
      expect(await overview()).toMatchObject({
        total: 1,
        expired: 1,
        later: 0,
      });
      await writer.query('COMMIT');
      expect(await overview()).toMatchObject({
        total: 1,
        expired: 0,
        later: 1,
      });
    } finally {
      await writer.query('ROLLBACK');
      writer.release();
    }
  });
});
