import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_OVERVIEW_FIXTURE_OPT_IN === 'isolated-overview-v1'
    ? describe
    : describe.skip;
suite('isolated overview repository acceptance', () => {
  let pool: Pool;
  let repository: AssetsRepository;
  const owner = randomBytes(12).toString('hex');
  const other = randomBytes(12).toString('hex');
  const empty = randomBytes(12).toString('hex');
  const limit = randomBytes(12).toString('hex');
  const input = {
    name: 'Synthetic router',
    category: 'network',
    serial: '%_1',
    status: 'stored' as const,
    notes: 'Synthetic only',
  };
  beforeAll(async () => {
    const raw = process.env.ASSET_OVERVIEW_FIXTURE_URL;
    const marker = process.env.ASSET_OVERVIEW_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_overview_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-overview-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_overview_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetsRepository({ pool } as PostgresDatabase);
    await repository.ready();
    for (const id of [owner, other, empty, limit]) {
      await pool.query(
        `INSERT INTO auth.accounts(id,email,username,name,password_hash)
        VALUES($1,$2,$3,'Synthetic category owner','not-a-login-hash')`,
        [id, `${id}@example.invalid`, `category_${id.slice(0, 16)}`],
      );
    }
    for (let i = 0; i < 51; i++) await repository.create(owner, input);
    await repository.create(owner, { ...input, status: 'repair' });
    await repository.create(owner, { ...input, category: 'Network' });
    await repository.create(owner, {
      ...input,
      category: '%_\u6a5f\u5668',
      status: 'retired',
    });
    await repository.create(other, { ...input, status: 'in_use' });
    for (let i = 0; i < 200; i++)
      await repository.create(limit, { ...input, category: `group-${i}` });
  }, 30000);
  afterAll(async () => {
    if (pool) await pool.end();
  });

  it('counts all pages and exact literal categories, not the current list filter', async () => {
    expect(
      (await repository.list(owner, { q: '', status: 'repair', offset: 0 }))
        .items,
    ).toHaveLength(1);
    const value = await repository.overview(owner);
    expect(value.total).toBe(54);
    expect(value.byStatus).toEqual({
      in_use: 0,
      stored: 52,
      repair: 1,
      retired: 1,
    });
    expect(value.byCategory).toEqual([
      { category: '%_\u6a5f\u5668', count: 1 },
      { category: 'Network', count: 1 },
      { category: 'network', count: 52 },
    ]);
    const snapshot = await repository.snapshot(owner);
    expect(snapshot.records).toHaveLength(54);
  });
  it('isolates identical owner labels and reports a genuinely empty account', async () => {
    expect(await repository.overview(other)).toEqual({
      complete: true,
      total: 1,
      byStatus: { in_use: 1, stored: 0, repair: 0, retired: 0 },
      byCategory: [{ category: 'network', count: 1 }],
    });
    expect(await repository.overview(empty)).toEqual({
      complete: true,
      total: 0,
      byStatus: { in_use: 0, stored: 0, repair: 0, retired: 0 },
      byCategory: [],
    });
  });
  it('allows exactly 200 categories and refuses the 201st without a partial result', async () => {
    expect((await repository.overview(limit)).byCategory).toHaveLength(200);
    await repository.create(limit, { ...input, category: 'group-201' });
    await expect(repository.overview(limit)).rejects.toMatchObject({
      status: 422,
    });
  });
  it('observes coherent counts before and after a concurrent transaction commit', async () => {
    const before = await repository.overview(owner);
    const connection = await pool.connect();
    let committed = false;
    try {
      await connection.query('BEGIN');
      await connection.query(
        "UPDATE assets.assets SET status='retired', category='transaction' WHERE owner_id=$1",
        [owner],
      );
      expect(await repository.overview(owner)).toEqual(before);
      await connection.query('COMMIT');
      committed = true;
      expect(await repository.overview(owner)).toEqual({
        complete: true,
        total: 54,
        byStatus: { in_use: 0, stored: 0, repair: 0, retired: 54 },
        byCategory: [{ category: 'transaction', count: 54 }],
      });
    } finally {
      if (!committed) await connection.query('ROLLBACK');
      connection.release();
    }
  });
});
