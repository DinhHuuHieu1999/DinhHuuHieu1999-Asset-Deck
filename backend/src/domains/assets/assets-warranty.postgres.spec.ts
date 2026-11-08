import { randomBytes } from 'node:crypto';
import { assetWarrantyWindow } from './asset-warranty';
import { AssetWarrantyQueryDto } from './asset-warranty.dto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_WARRANTY_FIXTURE_OPT_IN === 'isolated-warranty-v1'
    ? describe
    : describe.skip;
suite('isolated warranty repository acceptance', () => {
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
    const raw = process.env.ASSET_WARRANTY_FIXTURE_URL;
    const marker = process.env.ASSET_WARRANTY_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_warranty_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      'SELECT marker FROM public.asset_warranty_fixture_identity',
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
  function list(
    filter: 'expired' | 'expiring_soon',
    asOf = '2026-10-26',
    changes: Partial<AssetWarrantyQueryDto> = {},
    account = owner,
  ) {
    const query = Object.assign(
      new AssetWarrantyQueryDto(),
      { warranty: filter, asOf },
      changes,
    );
    return dates.warrantyList(
      account,
      query,
      assetWarrantyWindow(filter, asOf),
    );
  }

  it('isolates owners and excludes null; applies strict expiry and inclusive thirty-day boundaries', async () => {
    expect((await list('expired')).items).toEqual([]);
    const expired = await seed('2026-10-25');
    const today = await seed('2026-10-26');
    const horizon = await seed('2026-11-25');
    await seed('2026-11-26');
    await seed(null);
    const foreign = await seed('2026-10-25', other);
    expect((await list('expired')).items.map((r) => r.id)).toEqual([expired]);
    expect(
      new Set((await list('expiring_soon')).items.map((r) => r.id)),
    ).toEqual(new Set([today, horizon]));
    expect(
      (await list('expired', '2026-10-26', {}, other)).items.map((r) => r.id),
    ).toEqual([foreign]);
    const output = await list('expiring_soon');
    expect(output).toMatchObject({
      asOf: '2026-10-26',
      through: '2026-11-25',
      nextOffset: null,
    });
    expect(Object.keys(output.items[0]).sort()).toEqual(
      [
        'id',
        'name',
        'category',
        'serial',
        'status',
        'notes',
        'version',
        'createdAt',
        'updatedAt',
        'purchasedOn',
        'warrantyExpiresOn',
      ].sort(),
    );
  });

  it('intersects literal search/status/category before paging all fifty-one matches', async () => {
    for (let i = 0; i < 51; i++)
      await seed('2026-10-25', owner, 'Needle %_ ' + i);
    const decoys = [
      { ...input, name: 'Needle %_ foreign', category: 'Network' },
      { ...input, name: 'Needle %_ wrong status', status: 'repair' as const },
      { ...input, name: 'Needle XX not literal' },
    ];
    for (const input of decoys) {
      const row = await repository.create(owner, input);
      await dates.update(owner, row.id, {
        version: 1,
        purchasedOn: null,
        warrantyExpiresOn: '2026-10-25',
      });
    }
    await seed('2026-10-25', other, 'Needle %_ other owner');
    const query = {
      q: ' NEEDLE %_ ',
      category: ' network ',
      status: 'stored' as const,
    };
    const first = await list('expired', '2026-10-26', query);
    expect(first.items).toHaveLength(50);
    expect(first.nextOffset).toBe(50);
    const second = await list('expired', first.asOf, { ...query, offset: 50 });
    expect(second.items).toHaveLength(1);
    expect(second.nextOffset).toBeNull();
    expect(
      new Set([...first.items, ...second.items].map((r) => r.id)).size,
    ).toBe(51);
    expect(
      (await list('expired', '2026-10-26', { ...query, category: 'NETWORK' }))
        .items,
    ).toEqual([]);
    expect(
      (await list('expired', '2026-10-26', { q: "' OR 1=1 --" })).items,
    ).toEqual([]);
    expect((await list('expired', '2026-10-24', query)).items).toEqual([]);
    expect(
      (await list('expired', first.asOf, { ...query, offset: 50 })).items,
    ).toEqual(second.items);
  });

  it('uses Gregorian labels consistently at leap/century/year bounds without timezone rollover', async () => {
    const all: { id: string; end: string }[] = [];
    const pairs = [
      ['0001-01-01', '0001-01-31'],
      ['0099-12-20', '0100-01-19'],
      ['1900-02-01', '1900-03-03'],
      ['2000-02-01', '2000-03-02'],
      ['2024-02-01', '2024-03-02'],
      ['9999-12-20', '9999-12-31'],
    ];
    for (const [day, through] of pairs) {
      all.push(
        { id: await seed(day), end: day },
        { id: await seed(through), end: through },
      );
    }
    for (const [day, through] of pairs) {
      const page = await list('expiring_soon', day);
      expect(page.through).toBe(through);
      expect(new Set(page.items.map((r) => r.id))).toEqual(
        new Set(
          all.filter((r) => r.end >= day && r.end <= through).map((r) => r.id),
        ),
      );
      const expired = await list('expired', day);
      expect(new Set(expired.items.map((r) => r.id))).toEqual(
        new Set(all.filter((r) => r.end < day).map((r) => r.id)),
      );
    }
  });

  it('does not mutate data or change unfiltered v1/v2 export and overview', async () => {
    await seed(null);
    await seed('2026-10-25');
    await seed('2026-10-26');
    const before = (
      await pool.query(
        'SELECT json_agg(a ORDER BY id)::text AS value FROM assets.assets a',
      )
    ).rows[0].value;
    const v1 = (await repository.snapshot(owner)).records;
    const v2 = (await dates.exportSnapshot(owner)).records;
    const overview = await repository.overview(owner);
    await list('expired');
    await list('expiring_soon');
    await list('expired', '2026-10-26', { q: 'missing', offset: 50 });
    expect((await repository.snapshot(owner)).records).toEqual(v1);
    expect((await dates.exportSnapshot(owner)).records).toEqual(v2);
    expect(v1).toHaveLength(3);
    expect(v2).toHaveLength(3);
    expect(await repository.overview(owner)).toEqual(overview);
    expect(
      (
        await pool.query(
          'SELECT json_agg(a ORDER BY id)::text AS value FROM assets.assets a',
        )
      ).rows[0].value,
    ).toBe(before);
  });
});
