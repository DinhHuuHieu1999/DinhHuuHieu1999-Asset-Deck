import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { AssetQueryDto } from './assets.dto';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetCheckRepository } from './asset-check.repository';
import { AssetLocationRepository } from './asset-location.repository';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_CHECK_OVERVIEW_FIXTURE_OPT_IN ===
  'isolated-check-overview-v1'
    ? describe
    : describe.skip;
suite('isolated check overview repository acceptance', () => {
  let pool: Pool;
  let repository: AssetsRepository;
  const owner = randomBytes(12).toString('hex');
  const other = randomBytes(12).toString('hex');
  let dates: AssetDatesRepository;
  let locations: AssetLocationRepository;
  let checks: AssetCheckRepository;
  const previousFlag = process.env.ASSET_CHECK_ENABLED;
  const input = {
    name: 'Synthetic router',
    category: 'network',
    serial: '%_1',
    status: 'stored' as const,
    notes: 'Synthetic only',
  };
  beforeAll(async () => {
    const raw = process.env.ASSET_CHECK_OVERVIEW_FIXTURE_URL;
    const marker = process.env.ASSET_CHECK_OVERVIEW_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_check_overview_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-check-overview-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_check_overview_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetsRepository({ pool } as PostgresDatabase);
    await repository.ready();
    dates = new AssetDatesRepository({ pool } as PostgresDatabase);
    await dates.ready();
    locations = new AssetLocationRepository({ pool } as PostgresDatabase);
    await locations.ready();
    checks = new AssetCheckRepository({ pool } as PostgresDatabase);
    await checks.ready();
    process.env.ASSET_CHECK_ENABLED = 'true';
    for (const id of [owner, other]) {
      await pool.query(
        `INSERT INTO auth.accounts(id,email,username,name,password_hash)
        VALUES($1,$2,$3,'Synthetic category owner','not-a-login-hash')`,
        [id, `${id}@example.invalid`, `category_${id.slice(0, 16)}`],
      );
    }
  }, 30000);
  afterAll(async () => {
    if (previousFlag === undefined) delete process.env.ASSET_CHECK_ENABLED;
    else process.env.ASSET_CHECK_ENABLED = previousFlag;
    if (pool) await pool.end();
  });

  it('returns a complete empty owner partition', async () => {
    expect(await checks.overview(owner, '2024-02-29')).toEqual({
      complete: true,
      cutoff: '2024-02-29',
      total: 0,
      unknown: 0,
      before: 0,
      onOrAfter: 0,
    });
  });
  it('counts all pages with strict equality and owner isolation', async () => {
    for (let index = 0; index < 54; index++) {
      const row = await repository.create(owner, input);
      if (index < 53)
        await checks.update(owner, row.id, {
          version: 1,
          lastCheckedOn:
            index < 51
              ? '2024-02-28'
              : index === 51
                ? '2024-02-29'
                : '2024-03-01',
        });
    }
    await repository.create(other, input);
    expect(await checks.overview(owner, '2024-02-29')).toEqual({
      complete: true,
      cutoff: '2024-02-29',
      total: 54,
      unknown: 1,
      before: 51,
      onOrAfter: 2,
    });
    expect(await checks.overview(other, '2024-02-29')).toMatchObject({
      total: 1,
      unknown: 1,
      before: 0,
      onOrAfter: 0,
    });
    const query: AssetQueryDto = {
      q: '',
      status: '',
      category: '',
      offset: 0,
      sort: 'name_asc',
      checkMode: 'before',
      checkBefore: '2024-02-29',
    };
    const first = await repository.list(owner, query);
    const second = await repository.list(owner, { ...query, offset: 50 });
    expect(first.items).toHaveLength(50);
    expect(first.nextOffset).toBe(50);
    expect(second.items).toHaveLength(1);
    expect(second.nextOffset).toBeNull();
    expect(
      (
        await repository.list(owner, {
          ...query,
          checkMode: 'on_or_after',
          checkBefore: '',
          checkOnOrAfter: '2024-02-29',
        })
      ).items,
    ).toHaveLength(2);
  });
  it('preserves inclusive cutoff through all combined list scopes', async () => {
    const category = 'overview-combined';
    const ids: string[] = [];
    for (const lastCheckedOn of [
      '2024-02-28',
      '2024-02-29',
      '2024-03-01',
      null,
    ]) {
      const row = await repository.create(owner, { ...input, category });
      await dates.update(owner, row.id, {
        version: 1,
        purchasedOn: '2024-01-01',
        warrantyExpiresOn: '2025-01-01',
      });
      await locations.update(owner, row.id, {
        version: 2,
        location: 'Room %_1',
      });
      await checks.update(owner, row.id, { version: 3, lastCheckedOn });
      ids.push(row.id);
    }
    const query: AssetQueryDto = {
      q: '%_1',
      status: 'stored',
      category,
      offset: 0,
      sort: 'name_asc',
      checkMode: 'on_or_after',
      checkOnOrAfter: '2024-02-29',
    };
    const window = {
      filter: 'expired' as const,
      asOf: '2026-01-01',
      through: '2026-01-31',
    };
    for (const page of [
      await repository.list(owner, query),
      await dates.warrantyList(
        owner,
        { ...query, warranty: 'expired', asOf: window.asOf },
        window,
      ),
      await locations.list(owner, query, {
        mode: 'exact',
        location: 'Room %_1',
      }),
      await locations.list(
        owner,
        query,
        { mode: 'exact', location: 'Room %_1' },
        window,
      ),
    ])
      expect(new Set(page.items.map((item) => item.id))).toEqual(
        new Set(ids.slice(1, 3)),
      );
    expect((await repository.list(other, query)).items).toEqual([]);
  });
  it('aggregate reads leave all stored rows unchanged and reject invalid cutoff', async () => {
    const before = await pool.query('SELECT * FROM assets.assets ORDER BY id');
    await checks.overview(owner, '0001-01-01');
    await checks.overview(owner, '9999-12-31');
    await expect(checks.overview(owner, '2023-02-29')).rejects.toThrow();
    const after = await pool.query('SELECT * FROM assets.assets ORDER BY id');
    expect(after.rows).toEqual(before.rows);
  });
});
