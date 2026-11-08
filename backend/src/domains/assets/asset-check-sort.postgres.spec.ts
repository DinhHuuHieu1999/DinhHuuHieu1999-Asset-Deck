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
  process.env.ASSET_CHECK_SORT_FIXTURE_OPT_IN === 'isolated-check-sort-v1'
    ? describe
    : describe.skip;
suite('isolated inventory sort acceptance', () => {
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
  const seeded: { id: string; checked: string | null }[] = [];
  const previousFlag = process.env.ASSET_CHECK_ENABLED;
  beforeAll(async () => {
    const raw = process.env.ASSET_CHECK_SORT_FIXTURE_URL;
    const marker = process.env.ASSET_CHECK_SORT_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_check_sort_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-check-sort-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_check_sort_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    process.env.ASSET_CHECK_ENABLED = 'true';
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
    for (let i = 0; i < 56; i++) {
      const name = [
        'Alpha %_',
        'alpha %_',
        '\u00c9clair %_',
        '\u91cd\u590d %_',
      ][i % 4];
      const row = await repository.create(owner, { ...input, name });
      const checked = i < 51 ? '2023-12-31' : i < 54 ? '2024-02-29' : null;
      seeded.push({ id: row.id, checked });
      await pool.query(
        'UPDATE assets.assets SET last_checked_on=$1 WHERE id=$2',
        [checked, row.id],
      );
      await dates.update(owner, row.id, {
        version: 1,
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2027-02-28',
      });
      await locations.update(owner, row.id, { version: 2, location: '%_Room' });
    }
    await repository.create(other, { ...input, name: 'AAA %_' });
    await repository.create(owner, {
      ...input,
      name: 'Excluded',
      status: 'retired',
    });
    await pool.query(
      "UPDATE assets.assets SET updated_at='2026-01-01T00:00:00Z' WHERE owner_id=$1",
      [owner],
    );
  }, 30000);
  afterAll(async () => {
    if (pool) await pool.end();
    if (previousFlag === undefined) delete process.env.ASSET_CHECK_ENABLED;
    else process.env.ASSET_CHECK_ENABLED = previousFlag;
  });

  it.each(['regular', 'warranty', 'location', 'combined'] as const)(
    '%s sorts the complete filtered owner set before pagination without writes',
    async (kind) => {
      const before = await pool.query(
        'SELECT row_to_json(a) AS row FROM assets.assets a ORDER BY id',
      );
      const query: AssetQueryDto = {
        q: '%_',
        category: 'network',
        status: 'stored',
        offset: 0,
        sort: 'checked_asc',
      };
      const window = {
        filter: 'expiring_soon' as const,
        asOf: '2027-02-01',
        through: '2027-03-03',
      };
      const list = (offset: number) =>
        kind === 'regular'
          ? repository.list(owner, { ...query, offset })
          : kind === 'warranty'
            ? dates.warrantyList(
                owner,
                {
                  ...query,
                  offset,
                  warranty: 'expiring_soon',
                  asOf: '2027-02-01',
                },
                window,
              )
            : locations.list(
                owner,
                { ...query, offset },
                { mode: 'exact', location: '%_Room' },
                kind === 'combined' ? window : undefined,
              );
      const first = await list(0);
      const last = await list(50);
      const expected = [...seeded].sort(
        (a, b) =>
          (a.checked === b.checked
            ? 0
            : a.checked === null
              ? 1
              : b.checked === null
                ? -1
                : a.checked.localeCompare(b.checked)) ||
          a.id.localeCompare(b.id),
      );
      expect(first.items).toHaveLength(50);
      expect(first.nextOffset).toBe(50);
      expect(last.items).toHaveLength(6);
      expect(last.nextOffset).toBeNull();
      expect([...first.items, ...last.items].map((row) => row.id)).toEqual(
        expected.map((row) => row.id),
      );
      const after = await pool.query(
        'SELECT row_to_json(a) AS row FROM assets.assets a ORDER BY id',
      );
      expect(after.rows).toEqual(before.rows);
    },
  );
});
