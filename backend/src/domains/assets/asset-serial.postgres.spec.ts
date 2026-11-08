import { randomBytes } from 'node:crypto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetsRepository } from './assets.repository';

// A separate approved harness must provision and mark an isolated database.
// Default tests do not construct a pool, migrate, clean or delete anything.
const suite =
  process.env.ASSET_SERIAL_FIXTURE_OPT_IN === 'isolated-serial-v1'
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
    const raw = process.env.ASSET_SERIAL_FIXTURE_URL;
    const marker = process.env.ASSET_SERIAL_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture identity required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_serial_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
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
      application_name: 'asset-serial-isolated-acceptance',
    });
    const identity = await pool.query<{ name: string }>(
      'SELECT current_database() AS name',
    );
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Database mismatch');
    const ownership = await pool.query<{ marker: string }>(
      'SELECT marker FROM public.asset_serial_fixture_identity',
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

  it('compares case-sensitive literal serials, not wildcard or SQL patterns', async () => {
    expect(await repository.serialDuplicate(owner, 'AbC%_1')).toEqual({
      duplicate: true,
    });
    for (const serial of ['abc%_1', 'AbC', '%', '_', "' OR true --", ''])
      expect(await repository.serialDuplicate(owner, serial)).toEqual({
        duplicate: false,
      });
    expect(
      await repository.serialDuplicate(owner, String.fromCodePoint(0x1f527)),
    ).toEqual({ duplicate: true });
  });
  it('isolates owners and excludes only the supplied ID inside the owned rows', async () => {
    expect(await repository.serialDuplicate(owner, 'Foreign-only')).toEqual({
      duplicate: false,
    });
    expect(await repository.serialDuplicate(other, 'AbC%_1')).toEqual({
      duplicate: false,
    });
    expect(await repository.serialDuplicate(owner, 'AbC%_1', ownId)).toEqual({
      duplicate: false,
    });
    expect(
      await repository.serialDuplicate(owner, 'AbC%_1', foreignId),
    ).toEqual({ duplicate: true });
    expect(
      await repository.serialDuplicate(other, 'Foreign-only', foreignId),
    ).toEqual({ duplicate: false });
  });
  it('searches beyond the first page without mutating either account', async () => {
    const before = await repository.snapshot(owner);
    const theirs = await repository.snapshot(other);
    const page = await repository.list(owner, {
      q: '',
      status: '',
      category: '',
      offset: 0,
    });
    expect(page.items).toHaveLength(50);
    expect(page.items.map((row) => row.id)).not.toContain(ownId);
    expect(await repository.serialDuplicate(owner, 'AbC%_1')).toEqual({
      duplicate: true,
    });
    expect((await repository.snapshot(owner)).records).toEqual(before.records);
    expect((await repository.snapshot(other)).records).toEqual(theirs.records);
  });
  it('keeps duplicates allowed for create and optimistic update', async () => {
    const second = await repository.create(owner, {
      ...input,
      serial: 'AbC%_1',
    });
    expect(await repository.serialDuplicate(owner, 'AbC%_1', ownId)).toEqual({
      duplicate: true,
    });
    const updated = await repository.update(owner, second.id, second.version, {
      ...input,
      serial: 'AbC%_1',
      notes: 'duplicate allowed',
    });
    expect(updated?.notes).toBe('duplicate allowed');
    expect(updated?.version).toBe(second.version + 1);
  });
});
