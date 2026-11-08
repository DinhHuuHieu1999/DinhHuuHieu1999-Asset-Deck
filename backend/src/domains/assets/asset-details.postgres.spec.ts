import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_DETAILS_FIXTURE_OPT_IN === 'isolated-details-v1'
    ? describe
    : describe.skip;
suite('isolated serial repository acceptance', () => {
  let pool: Pool | undefined;
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
  let ownId: string;
  let foreignId: string;
  beforeAll(async () => {
    const raw = process.env.ASSET_DETAILS_FIXTURE_URL;
    const marker = process.env.ASSET_DETAILS_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_details_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-details-isolated-acceptance',
    });
    const identity = await pool.query<{ name: string }>(
      'SELECT current_database() AS name',
    );
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query<{ marker: string }>(
      'SELECT marker FROM public.asset_details_fixture_identity',
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
    ownId = (await repository.create(owner, { ...input, serial: 'AbC%_1' })).id;
    foreignId = (
      await repository.create(other, { ...input, serial: 'Foreign-only' })
    ).id;
    await repository.create(owner, { ...input, serial: '' });
    await repository.create(owner, {
      ...input,
      serial: String.fromCodePoint(0x1f527),
    });
    // The only matching serial becomes older than an entire list page.
    for (let i = 0; i < 55; i++)
      await repository.create(owner, { ...input, serial: 'filler-' + i });
  }, 30000);
  afterAll(async () => {
    if (pool !== undefined) await pool.end();
  });

  it('reads an owned record beyond the first list page', async () => {
    const page = await repository.list(owner, {
      q: '',
      status: '',
      category: '',
      offset: 0,
    });
    expect(page.items.map((row) => row.id)).not.toContain(ownId);
    expect((await repository.findOne(owner, ownId))?.serial).toBe('AbC%_1');
  });
  it('returns no record for foreign and absent IDs', async () => {
    expect(await repository.findOne(owner, foreignId)).toBeNull();
    expect(
      await repository.findOne(owner, '00000000-0000-4000-8000-000000000000'),
    ).toBeNull();
    expect(await repository.findOne(other, ownId)).toBeNull();
  });
  it('does not mutate either owner while reading', async () => {
    const before = await repository.snapshot(owner);
    const theirs = await repository.snapshot(other);
    await repository.findOne(owner, ownId);
    expect((await repository.snapshot(owner)).records).toEqual(before.records);
    expect((await repository.snapshot(other)).records).toEqual(theirs.records);
  });
  it('reads the latest committed version after update', async () => {
    const current = await repository.findOne(owner, ownId);
    if (!current) throw new Error('Missing synthetic record');
    const updated = await repository.update(owner, ownId, current.version, {
      ...input,
      notes: 'Refreshed details',
    });
    expect(await repository.findOne(owner, ownId)).toEqual(updated);
    expect(updated?.version).toBe(current.version + 1);
  });
});
