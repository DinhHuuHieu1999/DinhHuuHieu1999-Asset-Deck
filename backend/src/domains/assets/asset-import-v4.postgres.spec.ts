import { AssetImportV3Repository } from './asset-import-v3.repository';
import { randomBytes, randomUUID } from 'node:crypto';
import { Pool } from 'pg';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetImportRepository } from './asset-import.repository';
import { AssetImportV2Repository } from './asset-import-v2.repository';
import { AssetImportV4Repository } from './asset-import-v4.repository';

// Default runs never construct a pool. A separately approved harness must create
// an isolated database and marker; this suite never migrates or deletes data.
const enabled =
  process.env.ASSET_IMPORT_V4_FIXTURE_OPT_IN === 'isolated-import-v4-v1';
const suite = enabled ? describe : describe.skip;
suite('isolated PostgreSQL import acceptance', () => {
  let pool: Pool;
  let repository: AssetImportV4Repository;
  const owner = randomBytes(12).toString('hex');
  const other = randomBytes(12).toString('hex');
  const row = {
    name: 'Synthetic import',
    category: 'fixture',
    serial: '%_1',
    status: 'stored',
    notes: 'Synthetic only',
    purchasedOn: '2024-02-29',
    warrantyExpiresOn: '2028-01-01',
    location: 'Synthetic room %_1',
    lastCheckedDate: '2024-03-01',
  };
  const batch = (count = 1) => ({
    requestId: randomUUID(),
    records: Array.from({ length: count }, () => ({ ...row })),
  });
  async function counts(account: string) {
    const assets = await pool.query(
      'SELECT count(*)::int AS n FROM assets.assets WHERE owner_id=$1',
      [account],
    );
    const receipts = await pool.query(
      'SELECT count(*)::int AS n FROM assets.import_receipts WHERE owner_id=$1',
      [account],
    );
    return [assets.rows[0].n, receipts.rows[0].n];
  }
  beforeAll(async () => {
    const raw = process.env.ASSET_IMPORT_V4_FIXTURE_URL;
    const marker = process.env.ASSET_IMPORT_V4_FIXTURE_MARKER;
    if (!raw || !marker || !/^[0-9a-f]{32}$/.test(marker))
      throw new Error('Explicit fixture URL/marker required');
    const url = new URL(raw);
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !['127.0.0.1', 'localhost'].includes(url.hostname) ||
      !/^\/asset_import_v4_fixture_[0-9a-f]{12}$/.test(url.pathname) ||
      url.search ||
      url.hash
    ) {
      throw new Error('Refusing non-fixture PostgreSQL target');
    }
    pool = new Pool({
      connectionString: raw,
      max: 4,
      connectionTimeoutMillis: 5000,
      statement_timeout: 5000,
      application_name: 'asset-import-isolated-acceptance',
    });
    const identity = await pool.query('SELECT current_database() AS name');
    if (identity.rows[0]?.name !== url.pathname.slice(1))
      throw new Error('Fixture database mismatch');
    const ownership = await pool.query(
      'SELECT marker FROM public.asset_import_v4_fixture_identity',
    );
    if (ownership.rows.length !== 1 || ownership.rows[0].marker !== marker)
      throw new Error('Fixture ownership mismatch');
    repository = new AssetImportV4Repository({ pool } as PostgresDatabase);
    await repository.assertReady();
    for (const id of [owner, other]) {
      await pool.query(
        `INSERT INTO auth.accounts(id,email,username,name,password_hash)
        VALUES($1,$2,$3,'Synthetic import owner','not-a-login-hash')`,
        [id, `${id}@example.invalid`, `fixture_${id.slice(0, 16)}`],
      );
    }
  }, 15000);
  afterAll(async () => {
    if (pool) await pool.end();
  });

  it('adds 500 records and replays exact IDs without additional rows', async () => {
    const input = {
      ...batch(500),
      records: Array.from({ length: 500 }, (_, i) => ({
        ...row,
        purchasedOn: i % 2 ? null : '0001-01-01',
        warrantyExpiresOn: i % 2 ? null : '9999-12-31',
        location: i % 2 ? null : 'Synthetic room %_1',
        lastCheckedDate: i % 2 ? null : '9999-12-31',
      })),
    };
    const before = await counts(owner);
    const first = await repository.importBatch(owner, input);
    expect(first.recordCount).toBe(500);
    const dates = await pool.query(
      `SELECT id,purchased_on::text AS purchased_on,
      warranty_expires_on::text AS warranty_expires_on,location,last_checked_on::text AS last_checked_on,version
      FROM assets.assets WHERE id=ANY($1::uuid[])`,
      [first.recordIds],
    );
    const byId = new Map(dates.rows.map((r) => [r.id, r]));
    first.recordIds.forEach((id, i) => {
      expect(byId.get(id)).toMatchObject({
        purchased_on: input.records[i].purchasedOn,
        warranty_expires_on: input.records[i].warrantyExpiresOn,
        location: input.records[i].location,
        last_checked_on: input.records[i].lastCheckedDate,
        version: 1,
      });
    });
    expect(new Set(first.recordIds).size).toBe(500);
    expect(await repository.importBatch(owner, input)).toEqual(first);
    expect(await counts(owner)).toEqual([before[0] + 500, before[1] + 1]);
  }, 15000);
  it('rejects changed content for the same key without adding rows', async () => {
    const input = batch();
    await repository.importBatch(owner, input);
    const before = await counts(owner);
    await expect(
      repository.importBatch(owner, {
        ...input,
        records: [{ ...row, lastCheckedDate: null }],
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(await counts(owner)).toEqual(before);
  });
  it('conflicts across v1/v2/v3/v4 in both directions without changing rows', async () => {
    const legacy = new AssetImportRepository({ pool } as PostgresDatabase);
    const v1 = () => ({
      requestId: randomUUID(),
      records: [
        {
          name: row.name,
          category: row.category,
          serial: row.serial,
          status: row.status,
          notes: row.notes,
        },
      ],
    });
    const first = v1();
    await legacy.importBatch(owner, first);
    const before = await counts(owner);
    await expect(
      repository.importBatch(owner, {
        requestId: first.requestId,
        records: [{ ...row }],
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(await counts(owner)).toEqual(before);
    const second = batch();
    await repository.importBatch(owner, second);
    const after = await counts(owner);
    await expect(
      legacy.importBatch(owner, { ...v1(), requestId: second.requestId }),
    ).rejects.toMatchObject({ status: 409 });
    expect(await counts(owner)).toEqual(after);
    const v3 = new AssetImportV3Repository({ pool } as PostgresDatabase);
    const { lastCheckedDate: _manual, ...located } = row;
    const v3Input = { requestId: randomUUID(), records: [located] };
    await v3.importBatch(owner, v3Input);
    const beforeV4 = await counts(owner);
    await expect(
      repository.importBatch(owner, {
        requestId: v3Input.requestId,
        records: [{ ...row }],
      }),
    ).rejects.toMatchObject({ status: 409 });
    await expect(
      v3.importBatch(owner, {
        requestId: second.requestId,
        records: [located],
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(await counts(owner)).toEqual(beforeV4);
    const v2 = new AssetImportV2Repository({ pool } as PostgresDatabase);
    const { location: _location, lastCheckedDate: _check, ...dated } = row;
    const v2Input = { requestId: randomUUID(), records: [dated] };
    await v2.importBatch(owner, v2Input);
    const beforeV3 = await counts(owner);
    await expect(
      repository.importBatch(owner, {
        requestId: v2Input.requestId,
        records: [{ ...row }],
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(await counts(owner)).toEqual(beforeV3);
    await expect(
      v2.importBatch(owner, {
        requestId: second.requestId,
        records: [dated],
      }),
    ).rejects.toMatchObject({ status: 409 });
    expect(await counts(owner)).toEqual(beforeV3);
  });
  it('keeps the same key independent across two owners', async () => {
    const input = batch();
    const first = await repository.importBatch(owner, input);
    const second = await repository.importBatch(other, input);
    expect(second.recordIds).not.toEqual(first.recordIds);
    const result = await pool.query(
      'SELECT owner_id FROM assets.assets WHERE id=ANY($1::uuid[])',
      [second.recordIds],
    );
    expect(
      result.rows.map((value: { owner_id: string }) => value.owner_id),
    ).toEqual([other]);
  });
  it('serializes identical concurrent operations into one receipt', async () => {
    const input = batch(2);
    const before = await counts(owner);
    const [a, b] = await Promise.all([
      repository.importBatch(owner, input),
      repository.importBatch(owner, input),
    ]);
    expect(a).toEqual(b);
    expect(await counts(owner)).toEqual([before[0] + 2, before[1] + 1]);
  }, 15000);
  it('allows only one winner for concurrent conflicting content', async () => {
    const input = batch();
    const before = await counts(owner);
    const results = await Promise.allSettled([
      repository.importBatch(owner, input),
      repository.importBatch(owner, {
        ...input,
        records: [{ ...row, notes: 'conflict' }],
      }),
    ]);
    expect(
      results.filter((result) => result.status === 'fulfilled'),
    ).toHaveLength(1);
    expect(
      results.filter((result) => result.status === 'rejected'),
    ).toHaveLength(1);
    expect(await counts(owner)).toEqual([before[0] + 1, before[1] + 1]);
  }, 15000);
  it('rolls back all records and the receipt after an injected row failure', async () => {
    // Fixture-only fault injection, installed only after identity/ownership checks.
    const sentinel = `synthetic-fail-${randomBytes(8).toString('hex')}`;
    await pool.query(`CREATE FUNCTION assets.fixture_reject_import_row() RETURNS trigger
      LANGUAGE plpgsql AS $$ BEGIN
        IF NEW.name = TG_ARGV[0] THEN RAISE EXCEPTION 'synthetic row failure'; END IF;
        RETURN NEW;
      END $$`);
    await pool.query(`CREATE TRIGGER fixture_reject_import_row BEFORE INSERT ON assets.assets
      FOR EACH ROW EXECUTE FUNCTION assets.fixture_reject_import_row('${sentinel}')`);
    const before = await counts(owner);
    const input = {
      requestId: randomUUID(),
      records: [{ ...row }, { ...row, name: sentinel }],
    };
    await expect(repository.importBatch(owner, input)).rejects.toMatchObject({
      status: 503,
    });
    expect(await counts(owner)).toEqual(before);
    const replay = await repository.importBatch(owner, {
      ...input,
      records: [{ ...row }],
    });
    expect(replay.recordCount).toBe(1);
    expect(await counts(owner)).toEqual([before[0] + 1, before[1] + 1]);
  }, 15000);

  it('replays without duplicates after a real COMMIT loses its acknowledgment', async () => {
    const input = batch(2);
    const before = await counts(owner);
    let committed = false;
    const wrappedPool = new Proxy(pool, {
      get(target, property) {
        if (property === 'connect')
          return async () => {
            const client = await target.connect();
            return new Proxy(client, {
              get(connection, member) {
                if (member === 'query')
                  return async (...args: unknown[]) => {
                    const result = await Reflect.apply(
                      connection.query,
                      connection,
                      args,
                    );
                    if (args[0] === 'COMMIT') {
                      committed = true;
                      throw new Error(
                        'synthetic lost acknowledgment after commit',
                      );
                    }
                    return result;
                  };
                const value = Reflect.get(connection, member);
                return typeof value === 'function'
                  ? value.bind(connection)
                  : value;
              },
            });
          };
        const value = Reflect.get(target, property);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    const uncertainRepository = new AssetImportV4Repository({
      pool: wrappedPool,
    } as PostgresDatabase);
    await expect(
      uncertainRepository.importBatch(owner, input),
    ).rejects.toMatchObject({ status: 503 });
    expect(committed).toBe(true);
    expect(await counts(owner)).toEqual([before[0] + 2, before[1] + 1]);
    const receipt = await repository.importBatch(owner, input);
    expect(receipt.recordCount).toBe(2);
    const durable = await pool.query(
      'SELECT record_ids FROM assets.import_receipts WHERE owner_id=$1 AND request_id=$2',
      [owner, input.requestId],
    );
    expect(receipt.recordIds).toEqual(durable.rows[0].record_ids);
    expect(await counts(owner)).toEqual([before[0] + 2, before[1] + 1]);
  }, 15000);
});
