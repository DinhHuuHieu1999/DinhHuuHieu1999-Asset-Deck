import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_DATES_FIXTURE_OPT_IN === 'isolated-dates-v1'
    ? describe
    : describe.skip;
suite('isolated dates repository acceptance', () => {
  let pool: Pool;
  let repository: AssetsRepository;
  const owner = randomBytes(12).toString('hex');
  const other = randomBytes(12).toString('hex');
  let dates: AssetDatesRepository;
  const input = {
    name: 'Synthetic router',
    category: 'network',
    serial: '%_1',
    status: 'stored' as const,
    notes: 'Synthetic only',
  };
  beforeAll(async () => {
    const raw = process.env.ASSET_DATES_FIXTURE_URL;
    const marker = process.env.ASSET_DATES_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_dates_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
      !url.port ||
      ['5432', '5433'].includes(url.port) ||
      url.search ||
      url.hash
    )
      throw new Error('Refusing non-fixture target');
    pool = new Pool({
      connectionString: raw,
      max: 2,
      connectionTimeoutMillis: 5000,
      statement_timeout: 5000,
      application_name: 'asset-dates-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_dates_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetsRepository({ pool } as PostgresDatabase);
    await repository.ready();
    dates = new AssetDatesRepository({ pool } as PostgresDatabase);
    await dates.ready();
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

  it('isolates owners and missing records for both reads and writes', async () => {
    const row = await repository.create(owner, input);
    expect(await dates.read(owner, row.id)).toEqual({
      id: row.id,
      version: 1,
      purchasedOn: null,
      warrantyExpiresOn: null,
    });
    expect(await dates.read(other, row.id)).toBeNull();
    expect(
      await dates.update(other, row.id, {
        version: 1,
        purchasedOn: '2026-01-01',
        warrantyExpiresOn: null,
      }),
    ).toBeNull();
    expect(
      await dates.read(owner, '00000000-0000-4000-8000-000000000000'),
    ).toBeNull();
    expect((await dates.read(owner, row.id))?.version).toBe(1);
  });
  it('preserves dates on legacy edits and legacy fields on date edits', async () => {
    const row = await repository.create(owner, input);
    expect(
      await dates.update(owner, row.id, {
        version: 1,
        purchasedOn: '2000-02-29',
        warrantyExpiresOn: '9999-12-31',
      }),
    ).toEqual({
      id: row.id,
      version: 2,
      purchasedOn: '2000-02-29',
      warrantyExpiresOn: '9999-12-31',
    });
    const unchanged = await pool.query(
      'SELECT name,category,serial,status,notes FROM assets.assets WHERE id=$1',
      [row.id],
    );
    expect(unchanged.rows[0]).toEqual(input);
    expect(
      await repository.update(owner, row.id, 2, {
        ...input,
        name: 'Edited legacy name',
      }),
    ).not.toBeNull();
    expect(await dates.read(owner, row.id)).toEqual({
      id: row.id,
      version: 3,
      purchasedOn: '2000-02-29',
      warrantyExpiresOn: '9999-12-31',
    });
    expect(
      await dates.update(owner, row.id, {
        version: 2,
        purchasedOn: null,
        warrantyExpiresOn: null,
      }),
    ).toBeNull();
    expect(
      await dates.update(owner, row.id, {
        version: 3,
        purchasedOn: null,
        warrantyExpiresOn: null,
      }),
    ).toEqual({
      id: row.id,
      version: 4,
      purchasedOn: null,
      warrantyExpiresOn: null,
    });
    expect(
      (await pool.query('SELECT name FROM assets.assets WHERE id=$1', [row.id]))
        .rows[0].name,
    ).toBe('Edited legacy name');
  });
  it('allows only one concurrent update for the same shared version', async () => {
    const row = await repository.create(owner, input);
    const results = await Promise.all([
      dates.update(owner, row.id, {
        version: 1,
        purchasedOn: '2026-01-01',
        warrantyExpiresOn: null,
      }),
      dates.update(owner, row.id, {
        version: 1,
        purchasedOn: '2026-02-01',
        warrantyExpiresOn: null,
      }),
    ]);
    const winners = results.filter((value) => value !== null);
    expect(winners).toHaveLength(1);
    expect(await dates.read(owner, row.id)).toEqual(winners[0]);
    expect(winners[0]?.version).toBe(2);
  });
  it('enforces SQL calendar ranges and order independently of application validation', async () => {
    const row = await repository.create(owner, input);
    for (const [purchase, warranty] of [
      ['1900-02-29', null],
      ['infinity', null],
      [null, '-infinity'],
      ['10000-01-01', null],
      ['0001-01-01 BC', null],
      ['2026-02-01', '2026-01-01'],
    ]) {
      await expect(
        pool.query(
          'UPDATE assets.assets SET purchased_on=$2::date,warranty_expires_on=$3::date WHERE id=$1',
          [row.id, purchase, warranty],
        ),
      ).rejects.toBeDefined();
    }
    expect(await dates.read(owner, row.id)).toEqual({
      id: row.id,
      version: 1,
      purchasedOn: null,
      warrantyExpiresOn: null,
    });
    expect(
      await dates.update(owner, row.id, {
        version: 1,
        purchasedOn: '0001-01-01',
        warrantyExpiresOn: '0001-01-01',
      }),
    ).toMatchObject({
      purchasedOn: '0001-01-01',
      warrantyExpiresOn: '0001-01-01',
    });
  });
});
