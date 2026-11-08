import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_CATEGORY_FIXTURE_OPT_IN === 'isolated-category-v1'
    ? describe
    : describe.skip;
suite('isolated category repository acceptance', () => {
  let pool: Pool;
  let repository: AssetsRepository;
  const owner = randomBytes(12).toString('hex');
  const other = randomBytes(12).toString('hex');
  const input = {
    name: 'Synthetic router',
    category: 'network',
    serial: '%_1',
    status: 'stored' as const,
    notes: 'Synthetic only',
  };
  const list = (
    category = '',
    q = '',
    status: '' | 'stored' | 'repair' = '',
    offset = 0,
  ) => repository.list(owner, { category, q, status, offset });

  beforeAll(async () => {
    const raw = process.env.ASSET_CATEGORY_FIXTURE_URL;
    const marker = process.env.ASSET_CATEGORY_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_category_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-category-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_category_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetsRepository({ pool } as PostgresDatabase);
    await repository.ready();
    for (const id of [owner, other]) {
      await pool.query(
        `INSERT INTO auth.accounts(id,email,username,name,password_hash)
        VALUES($1,$2,$3,'Synthetic category owner','not-a-login-hash')`,
        [id, `${id}@example.invalid`, `category_${id.slice(0, 16)}`],
      );
    }
    for (let i = 0; i < 51; i++) await repository.create(owner, input);
    await repository.create(other, input);
    await repository.create(owner, { ...input, category: 'Network' });
    await repository.create(owner, {
      ...input,
      category: 'network',
      status: 'repair',
    });
    await repository.create(owner, { ...input, category: "%_' OR true --" });
    await repository.create(owner, { ...input, category: 'Thi?t b?' });
    // Newer nonmatching rows must not consume the filtered page.
    for (let i = 0; i < 51; i++)
      await repository.create(owner, { ...input, category: 'other' });
  }, 30000);
  afterAll(async () => {
    if (pool) await pool.end();
  });

  it('filters before pagination and combines literal search/status', async () => {
    const first = await list('network', '%_', 'stored');
    expect(first.items).toHaveLength(50);
    expect(first.nextOffset).toBe(50);
    const second = await list('network', '%_', 'stored', 50);
    expect(second.items).toHaveLength(1);
    expect(second.nextOffset).toBeNull();
    expect(
      new Set([...first.items, ...second.items].map((row) => row.id)).size,
    ).toBe(51);
    expect(
      [...first.items, ...second.items].every(
        (row) => row.category === 'network',
      ),
    ).toBe(true);
    expect((await list('network', 'not-found', 'stored')).items).toEqual([]);
    expect((await list('network', '', 'repair')).items).toHaveLength(1);
  });
  it('preserves case and treats whitespace, SQL punctuation and Unicode literally', async () => {
    expect((await list(' Network ')).items).toHaveLength(1);
    expect((await list("%_' OR true --")).items).toHaveLength(1);
    expect((await list('Thi?t b?')).items).toHaveLength(1);
    expect((await list('NETWORK')).items).toEqual([]);
  });
  it('isolates owners even with identical labels and filters', async () => {
    const theirs = await repository.list(other, {
      category: 'network',
      q: '',
      status: '',
      offset: 0,
    });
    expect(theirs.items).toHaveLength(1);
    const ours = await list('network');
    expect(ours.items.map((row) => row.id)).not.toContain(theirs.items[0].id);
  });
  it('empty category is unfiltered and snapshot is independent of list filters', async () => {
    const before = await repository.snapshot(owner);
    expect(before.records).toHaveLength(106);
    expect((await list('')).items).toHaveLength(50);
    expect((await list('   ')).items).toHaveLength(50);
    expect((await list('missing')).items).toEqual([]);
    const after = await repository.snapshot(owner);
    expect(after.records).toEqual(before.records);
  });
});
