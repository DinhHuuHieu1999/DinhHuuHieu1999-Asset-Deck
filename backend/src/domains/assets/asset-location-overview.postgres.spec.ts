import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetLocationRepository } from './asset-location.repository';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_LOCATION_OVERVIEW_FIXTURE_OPT_IN === 'isolated-location-overview-v1'
    ? describe
    : describe.skip;
suite('isolated location repository acceptance', () => {
  let pool: Pool;
  let repository: AssetsRepository;
  const owner = randomBytes(12).toString('hex');
  const other = randomBytes(12).toString('hex');
  let dates: AssetDatesRepository;
  let locations: AssetLocationRepository;
  const input = {
    name: 'Synthetic router',
    category: 'network',
    serial: '%_1',
    status: 'stored' as const,
    notes: 'Synthetic only',
  };
  beforeAll(async () => {
    const raw = process.env.ASSET_LOCATION_OVERVIEW_FIXTURE_URL;
    const marker = process.env.ASSET_LOCATION_OVERVIEW_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_location_overview_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-location-overview-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_location_overview_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetsRepository({ pool } as PostgresDatabase);
    await repository.ready();
    dates = new AssetDatesRepository({ pool } as PostgresDatabase);
    await dates.ready();
    locations = new AssetLocationRepository({ pool } as PostgresDatabase);
    await locations.ready();
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

  it('returns complete zero counts for an empty authenticated owner', async () => {
    expect(await locations.overview(owner)).toEqual({
      complete: true,
      total: 0,
      unknown: 0,
      locations: [],
    });
  });
  it('counts more than one page and keeps literal/case labels and owners separate', async () => {
    const account = randomBytes(12).toString('hex');
    await pool.query(
      `INSERT INTO auth.accounts(id,email,username,name,password_hash) VALUES($1,$2,$3,'Synthetic','not-a-login-hash')`,
      [account, account + '@example.invalid', account],
    );
    await pool.query(
      `INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes,location) SELECT gen_random_uuid(),$1,'Synthetic','fixture','','stored','',CASE WHEN n<=55 THEN 'Room %_1' WHEN n=56 THEN 'room %_1' ELSE NULL END FROM generate_series(1,60) AS n`,
      [account],
    );
    const foreign = await repository.create(other, input);
    await locations.update(other, foreign.id, {
      version: 1,
      location: 'Foreign only',
    });
    expect(await locations.overview(account)).toEqual({
      complete: true,
      total: 60,
      unknown: 4,
      locations: [
        { location: 'Room %_1', count: 55 },
        { location: 'room %_1', count: 1 },
      ],
    });
    expect((await locations.overview(other)).locations).toContainEqual({
      location: 'Foreign only',
      count: 1,
    });
  });
  it('reflects explicit location clear without changing other fields', async () => {
    const row = await repository.create(owner, input);
    await locations.update(owner, row.id, { version: 1, location: 'Office' });
    expect((await locations.overview(owner)).locations).toContainEqual({
      location: 'Office',
      count: 1,
    });
    await locations.update(owner, row.id, { version: 2, location: null });
    expect(await locations.overview(owner)).toEqual({
      complete: true,
      total: 1,
      unknown: 1,
      locations: [],
    });
    expect(
      (
        await repository.list(owner, {
          q: '',
          status: '',
          category: '',
          offset: 0,
        })
      ).items[0].name,
    ).toBe(input.name);
  });
  it('accepts 1000 labels but refuses additional groups without partial output', async () => {
    const account = randomBytes(12).toString('hex');
    await pool.query(
      `INSERT INTO auth.accounts(id,email,username,name,password_hash) VALUES($1,$2,$3,'Synthetic','not-a-login-hash')`,
      [account, account + '@example.invalid', account],
    );
    await pool.query(
      `INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes,location) SELECT gen_random_uuid(),$1,'Synthetic','fixture','','stored','','Room '||n FROM generate_series(1,1000) AS n`,
      [account],
    );
    expect((await locations.overview(account)).locations).toHaveLength(1000);
    const extra = await repository.create(account, input);
    await locations.update(account, extra.id, {
      version: 1,
      location: 'Extra',
    });
    await expect(locations.overview(account)).rejects.toThrow(
      'no partial overview',
    );
  });
});
