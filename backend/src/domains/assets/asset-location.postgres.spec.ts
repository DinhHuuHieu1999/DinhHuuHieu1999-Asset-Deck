import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { AssetQueryDto } from './assets.dto';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetLocationRepository } from './asset-location.repository';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_LOCATION_FIXTURE_OPT_IN === 'isolated-location-v1'
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
    const raw = process.env.ASSET_LOCATION_FIXTURE_URL;
    const marker = process.env.ASSET_LOCATION_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_location_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-location-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_location_fixture_identity',
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

  it('isolates read/write owners and preserves base fields and dates', async () => {
    const row = await repository.create(owner, input);
    expect(await locations.read(other, row.id)).toBeNull();
    expect(
      await locations.update(other, row.id, { version: 1, location: 'Other' }),
    ).toBeNull();
    await dates.update(owner, row.id, {
      version: 1,
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: '2027-02-28',
    });
    expect(
      await locations.update(owner, row.id, {
        version: 2,
        location: ' Office ',
      }),
    ).toEqual({ id: row.id, version: 3, location: 'Office' });
    expect(await dates.read(owner, row.id)).toEqual({
      id: row.id,
      version: 3,
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: '2027-02-28',
    });
    const unchanged = await pool.query(
      'SELECT name,category,serial,status,notes FROM assets.assets WHERE id=$1',
      [row.id],
    );
    expect(unchanged.rows[0]).toEqual(input);
    expect(
      await locations.read(owner, '00000000-0000-4000-8000-000000000000'),
    ).toBeNull();
  });

  it('uses one shared optimistic version across simultaneous date and location edits', async () => {
    const row = await repository.create(owner, input);
    const results = await Promise.all([
      locations.update(owner, row.id, { version: 1, location: 'Warehouse' }),
      dates.update(owner, row.id, {
        version: 1,
        purchasedOn: null,
        warrantyExpiresOn: '2027-02-28',
      }),
    ]);
    expect(results.filter(Boolean)).toHaveLength(1);
    expect((await locations.read(owner, row.id))?.version).toBe(2);
    expect(
      await locations.update(owner, row.id, { version: 1, location: 'Stale' }),
    ).toBeNull();
  });

  it('combines literal exact/unknown, owner, status, category and warranty before paging', async () => {
    const account = randomBytes(12).toString('hex');
    await pool.query(
      `INSERT INTO auth.accounts(id,email,username,name,password_hash)
      VALUES($1,$2,$3,'Synthetic paging owner','not-a-login-hash')`,
      [account, `${account}@example.invalid`, `paging_${account.slice(0, 16)}`],
    );
    for (let i = 0; i < 52; i++) {
      const row = await repository.create(account, {
        ...input,
        name: `Literal %_ ${i}`,
      });
      await locations.update(account, row.id, {
        version: 1,
        location: i === 51 ? null : '%_Room',
      });
      await dates.update(account, row.id, {
        version: 2,
        purchasedOn: null,
        warrantyExpiresOn: '2027-02-28',
      });
    }
    const query: AssetQueryDto = {
      q: '%_',
      status: 'stored',
      category: 'network',
      offset: 0,
    };
    const window = {
      filter: 'expiring_soon' as const,
      asOf: '2027-02-01',
      through: '2027-03-03',
    };
    const first = await locations.list(
      account,
      query,
      { mode: 'exact', location: '%_Room' },
      window,
    );
    expect(first.items).toHaveLength(50);
    expect(first.nextOffset).toBe(50);
    const last = await locations.list(
      account,
      { ...query, offset: 50 },
      { mode: 'exact', location: '%_Room' },
      window,
    );
    expect(last.items).toHaveLength(1);
    expect(last.nextOffset).toBeNull();
    expect(
      new Set([...first.items, ...last.items].map((row) => row.id)).size,
    ).toBe(51);
    expect(
      (
        await locations.list(account, query, {
          mode: 'unknown',
          location: null,
        })
      ).items,
    ).toHaveLength(1);
    expect(
      (
        await locations.list(account, query, {
          mode: 'exact',
          location: '%_room',
        })
      ).items,
    ).toHaveLength(0);
    expect(
      (
        await locations.list(other, query, {
          mode: 'exact',
          location: '%_Room',
        })
      ).items,
    ).toHaveLength(0);
    expect(
      (
        await locations.list(
          account,
          { ...query, status: 'retired' },
          { mode: 'all', location: null },
        )
      ).items,
    ).toHaveLength(0);
  });

  it('clears explicitly, preserves location on legacy edits, and rejects invalid direct SQL', async () => {
    const row = await repository.create(owner, input);
    await locations.update(owner, row.id, {
      version: 1,
      location: 'Warehouse',
    });
    await repository.update(owner, row.id, 2, {
      ...input,
      name: 'Edited base',
    });
    expect((await locations.read(owner, row.id))?.location).toBe('Warehouse');
    for (const label of ['', ' padded ', 'x'.repeat(121), 'Room\nA']) {
      await expect(
        pool.query('UPDATE assets.assets SET location=$2 WHERE id=$1', [
          row.id,
          label,
        ]),
      ).rejects.toThrow();
    }
    expect(
      await locations.update(owner, row.id, { version: 3, location: null }),
    ).toEqual({ id: row.id, version: 4, location: null });
  });
});
