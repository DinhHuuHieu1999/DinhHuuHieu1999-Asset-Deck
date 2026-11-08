import { randomBytes, randomUUID } from 'node:crypto';
import { ConflictException, NotFoundException } from '@nestjs/common';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetSavedFilterRepository } from './asset-saved-filter.repository';

// No pool or SQL is constructed without the separately approved owned fixture.
const suite =
  process.env.ASSET_SAVED_FILTERS_FIXTURE_OPT_IN === 'isolated-saved-filters-v1'
    ? describe
    : describe.skip;
suite('isolated account saved filters acceptance', () => {
  let pool: Pool;
  let repository: AssetSavedFilterRepository;
  const query = {
    q: '%_',
    status: '',
    category: '',
    sort: 'checked_asc',
    locationMode: 'exact',
    location: 'Room %_1',
    warranty: 'expired',
    asOf: '2024-02-29',
    checkMode: 'before',
    checkBefore: '2024-03-01',
    checkOnOrAfter: '',
  };
  beforeAll(async () => {
    const raw = process.env.ASSET_SAVED_FILTERS_FIXTURE_URL;
    const marker = process.env.ASSET_SAVED_FILTERS_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_saved_filters_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-saved-filters-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_saved_filters_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetSavedFilterRepository({ pool } as PostgresDatabase);
    await repository.ready();
  });
  afterAll(async () => {
    if (pool) await pool.end();
  });
  async function account() {
    const id = randomBytes(12).toString('hex');
    await pool.query(
      `INSERT INTO auth.accounts(id,email,username,name,password_hash)
       VALUES($1,$2,$3,'Synthetic saved filters','not-a-login-hash')`,
      [id, `${id}@example.invalid`, `saved_${id.slice(0, 16)}`],
    );
    return id;
  }
  it('round-trips fixed dates and literals without exposing another owner', async () => {
    const owner = await account(),
      other = await account();
    const saved = await repository.create(owner, 'Literal view', query);
    expect(await repository.list(owner)).toEqual([saved]);
    expect(saved.query).toEqual(query);
    expect(await repository.list(other)).toEqual([]);
    await expect(repository.change(other, saved.id, 1)).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(await repository.list(owner)).toEqual([saved]);
  });
  it('serializes concurrent creates at the twenty-definition capacity', async () => {
    const owner = await account();
    for (let i = 0; i < 19; i++)
      await repository.create(owner, `View ${i}`, query);
    const results = await Promise.allSettled([
      repository.create(owner, 'Concurrent A', query),
      repository.create(owner, 'Concurrent B', query),
    ]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    const rejected = results.find((r) => r.status === 'rejected');
    expect(rejected?.status === 'rejected' && rejected.reason).toBeInstanceOf(
      ConflictException,
    );
    expect(await repository.list(owner)).toHaveLength(20);
  });
  it('allows one concurrent replacement and rejects stale delete', async () => {
    const owner = await account();
    const saved = await repository.create(owner, 'Original', query);
    const results = await Promise.allSettled(
      ['A', 'B'].map((name) =>
        repository.change(owner, saved.id, 1, { name, query }),
      ),
    );
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    const rejected = results.find((r) => r.status === 'rejected');
    expect(rejected?.status === 'rejected' && rejected.reason).toBeInstanceOf(
      ConflictException,
    );
    await expect(repository.change(owner, saved.id, 1)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect((await repository.list(owner))[0].version).toBe(2);
  });
  it('deletes only the definition and a new repository sees committed state', async () => {
    const owner = await account();
    await pool.query(
      `INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes)
       VALUES($1,$2,'Preserved asset','fixture','%_1','stored','Must not change')`,
      [randomUUID(), owner],
    );
    const snapshot =
      'SELECT to_jsonb(a) AS record FROM assets.assets a ORDER BY id';
    const before = await pool.query(snapshot);
    const saved = await repository.create(owner, 'Temporary', query);
    const reopened = new AssetSavedFilterRepository({
      pool,
    } as PostgresDatabase);
    expect(await reopened.list(owner)).toEqual([saved]);
    await reopened.change(owner, saved.id, 1);
    expect(await reopened.list(owner)).toEqual([]);
    expect((await pool.query(snapshot)).rows).toEqual(before.rows);
  });
});
