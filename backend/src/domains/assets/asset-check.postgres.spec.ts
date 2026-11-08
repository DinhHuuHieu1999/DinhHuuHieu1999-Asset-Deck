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
  process.env.ASSET_CHECK_FIXTURE_OPT_IN === 'isolated-check-v1'
    ? describe
    : describe.skip;
suite('isolated manual check repository acceptance', () => {
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
    const raw = process.env.ASSET_CHECK_FIXTURE_URL;
    const marker = process.env.ASSET_CHECK_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_check_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-check-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_check_fixture_identity',
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

  it('isolates owners and preserves dates, location and base fields', async () => {
    const row = await repository.create(owner, input);
    await dates.update(owner, row.id, {
      version: 1,
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: '2027-02-28',
    });
    await locations.update(owner, row.id, { version: 2, location: 'Room %_1' });
    expect(await checks.read(other, row.id)).toBeNull();
    expect(
      await checks.update(other, row.id, {
        version: 3,
        lastCheckedOn: '2024-03-01',
      }),
    ).toBeNull();
    expect(
      await checks.update(owner, row.id, {
        version: 3,
        lastCheckedOn: '2024-03-01',
      }),
    ).toEqual({ id: row.id, version: 4, lastCheckedOn: '2024-03-01' });
    expect(
      await checks.update(owner, row.id, { version: 3, lastCheckedOn: null }),
    ).toBeNull();
    expect(await dates.read(owner, row.id)).toMatchObject({
      version: 4,
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: '2027-02-28',
    });
    expect(await locations.read(owner, row.id)).toMatchObject({
      version: 4,
      location: 'Room %_1',
    });
    expect(
      (
        await pool.query(
          'SELECT name,category,serial,status,notes FROM assets.assets WHERE owner_id=$1 AND id=$2',
          [owner, row.id],
        )
      ).rows[0],
    ).toEqual(input);
  });
  it('two concurrent writes share one version and only one wins', async () => {
    const row = await repository.create(owner, input);
    const results = await Promise.all([
      checks.update(owner, row.id, { version: 1, lastCheckedOn: '2024-01-01' }),
      checks.update(owner, row.id, { version: 1, lastCheckedOn: '2024-01-02' }),
    ]);
    expect(results.filter(Boolean)).toHaveLength(1);
    expect((await checks.read(owner, row.id))?.version).toBe(2);
  });
  it('clear becomes Unknown without modifying preserved fields', async () => {
    const row = await repository.create(owner, input);
    await checks.update(owner, row.id, {
      version: 1,
      lastCheckedOn: '2024-01-01',
    });
    expect(
      await checks.update(owner, row.id, { version: 2, lastCheckedOn: null }),
    ).toEqual({ id: row.id, version: 3, lastCheckedOn: null });
    expect(
      (
        await pool.query(
          'SELECT name,category,serial,status,notes FROM assets.assets WHERE owner_id=$1 AND id=$2',
          [owner, row.id],
        )
      ).rows[0],
    ).toEqual(input);
  });
  it('filters Unknown before pagination and isolates literal search scope', async () => {
    const category = 'check-pagination';
    for (let index = 0; index < 52; index++) {
      const row = await repository.create(owner, {
        ...input,
        name: `Unknown ${index}`,
        category,
      });
      if (index === 0)
        await checks.update(owner, row.id, {
          version: 1,
          lastCheckedOn: '2024-01-01',
        });
    }
    await repository.create(other, { ...input, category });
    const query: AssetQueryDto = {
      q: '%_1',
      status: 'stored',
      category,
      offset: 0,
      sort: 'name_asc',
      checkMode: 'unchecked',
    };
    const first = await repository.list(owner, query);
    expect(first.items).toHaveLength(50);
    expect(first.nextOffset).toBe(50);
    const second = await repository.list(owner, { ...query, offset: 50 });
    expect(second.items).toHaveLength(1);
    expect(second.nextOffset).toBeNull();
    expect(
      new Set([...first.items, ...second.items].map((item) => item.id)).size,
    ).toBe(51);
  });
  it('checked-before excludes boundary/Unknown and filters before pagination per owner', async () => {
    const category = 'before-pagination';
    const matching: string[] = [];
    for (let index = 0; index < 54; index++) {
      const row = await repository.create(owner, {
        ...input,
        name: `Before ${String(index).padStart(3, '0')}`,
        category,
      });
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
      if (index < 51) matching.push(row.id);
    }
    const foreign = await repository.create(other, { ...input, category });
    await checks.update(other, foreign.id, {
      version: 1,
      lastCheckedOn: '2024-02-28',
    });
    const query: AssetQueryDto = {
      q: '%_1',
      status: 'stored',
      category,
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
    expect([...first.items, ...second.items].map((item) => item.id)).toEqual(
      matching,
    );
    expect(
      (await repository.list(other, query)).items.map((item) => item.id),
    ).toEqual([foreign.id]);
  });
  it('combines cutoff with literal location and warranty without mutating rows', async () => {
    const category = 'before-combined';
    const ids: string[] = [];
    for (const lastCheckedOn of ['2024-02-28', '2024-02-29', null]) {
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
      checkMode: 'before',
      checkBefore: '2024-02-29',
    };
    const window = {
      filter: 'expired' as const,
      asOf: '2026-01-01',
      through: '2026-01-31',
    };
    const before = await pool.query(
      'SELECT * FROM assets.assets WHERE owner_id=$1 AND category=$2 ORDER BY id',
      [owner, category],
    );
    for (const result of [
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
      expect(result.items.map((item) => item.id)).toEqual([ids[0]]);
    expect(
      (
        await locations.list(
          other,
          query,
          { mode: 'exact', location: 'Room %_1' },
          window,
        )
      ).items,
    ).toEqual([]);
    const after = await pool.query(
      'SELECT * FROM assets.assets WHERE owner_id=$1 AND category=$2 ORDER BY id',
      [owner, category],
    );
    expect(after.rows).toEqual(before.rows);
  });
});
