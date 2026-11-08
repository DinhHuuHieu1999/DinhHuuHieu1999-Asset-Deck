import { prepareAssetImportV2 } from './asset-import-v2';
import 'reflect-metadata';
import { ConflictException, ServiceUnavailableException } from '@nestjs/common';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetImportV3Repository } from './asset-import-v3.repository';
import { prepareAssetImportV3 } from './asset-import-v3';
import { prepareAssetImport } from './asset-import';

const owner = '0123456789abcdef01234567';
const input = {
  requestId: '7971aec3-ed1b-4ed0-9de5-e9ad617d752e',
  records: [
    {
      name: 'Synthetic',
      serial: '%_1',
      category: 'test',
      status: 'stored',
      notes: '',
      purchasedOn: '2024-02-29',
      warrantyExpiresOn: '2028-01-01',
      location: 'Room %_1',
    },
  ],
};
function fixture() {
  const client = {
    query: jest.fn().mockResolvedValue({ rows: [], rowCount: 1 }),
    release: jest.fn(),
  };
  const pool = {
    connect: jest.fn().mockResolvedValue(client),
    query: jest.fn(),
  };
  const repository = new AssetImportV3Repository({
    pool,
  } as unknown as PostgresDatabase);
  return { client, pool, repository };
}

describe('Add-only transaction source (mocked PostgreSQL; no database)', () => {
  it.each(['v1', 'changed purchase', 'changed warranty'])(
    'refuses an existing key with %s content without inserting or committing',
    async (scenario) => {
      const { repository, client } = fixture();
      const record = input.records[0];
      const digest =
        scenario === 'v1'
          ? prepareAssetImport({
              requestId: input.requestId,
              records: [
                {
                  name: record.name,
                  category: record.category,
                  serial: record.serial,
                  status: record.status,
                  notes: record.notes,
                },
              ],
            }).digest
          : prepareAssetImportV3({
              ...input,
              records: [
                {
                  ...record,
                  ...(scenario === 'changed purchase'
                    ? { purchasedOn: '2024-02-28' }
                    : { warrantyExpiresOn: '2028-01-02' }),
                },
              ],
            }).digest;
      client.query
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({
          rows: [
            { digest, recordIds: ['01234567-89ab-4cde-8123-456789abcdef'] },
          ],
        });
      await expect(repository.importBatch(owner, input)).rejects.toThrow(
        ConflictException,
      );
      expect(
        client.query.mock.calls.map(([sql]) => sql.split(/\s+/u)[0]),
      ).toEqual(['BEGIN', 'INSERT', 'SELECT', 'ROLLBACK']);
      expect(client.release).toHaveBeenCalledWith(false);
    },
  );
  it('inserts both dates atomically without a follow-up version update', async () => {
    const { repository, client } = fixture();
    client.query.mockResolvedValueOnce({ rows: [] }).mockResolvedValueOnce({
      rows: [{ request_id: input.requestId }],
      rowCount: 1,
    });
    await repository.importBatch(owner, input);
    const [sql, args] = client.query.mock.calls[2];
    expect(sql).toContain('purchased_on,warranty_expires_on');
    expect(sql).toContain('"purchasedOn" date,"warrantyExpiresOn" date');
    const rows = JSON.parse(args[1]);
    expect(rows[0].purchasedOn).toBe('2024-02-29');
    expect(rows[0].warrantyExpiresOn).toBe('2028-01-01');
    expect(rows[0].location).toBe('Room %_1');
    expect(sql).toContain('warranty_expires_on,location)');
    expect(sql).toContain('x."warrantyExpiresOn",x.location');
    expect(client.query.mock.calls.map(([statement]) => statement)).not.toEqual(
      expect.arrayContaining([expect.stringMatching(/^UPDATE /u)]),
    );
  });
  it('probes required columns without reading records or writing schema', async () => {
    const { repository, pool, client } = fixture();
    pool.query.mockResolvedValue({ rows: [] });
    await repository.assertReady();
    expect(pool.query).toHaveBeenCalledTimes(2);
    expect(pool.query.mock.calls[0][0]).toContain('FROM assets.assets LIMIT 0');
    expect(pool.query.mock.calls[1][0]).toContain(
      'FROM assets.import_receipts LIMIT 0',
    );
    for (const [sql] of pool.query.mock.calls) {
      expect(sql).toMatch(/^SELECT /u);
      expect(sql).not.toMatch(/\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER)\b/iu);
    }
    expect(pool.connect).not.toHaveBeenCalled();
    expect(client.query).not.toHaveBeenCalled();
  });

  it.each([0, 1])(
    'fails closed and sanitizes prerequisite query %s failure',
    async (failed) => {
      const { repository, pool } = fixture();
      if (failed === 1) pool.query.mockResolvedValueOnce({ rows: [] });
      pool.query.mockRejectedValueOnce(new Error('private database details'));
      await expect(repository.assertReady()).rejects.toThrow(
        'Asset import schema is not ready',
      );
      expect(pool.query).toHaveBeenCalledTimes(failed + 1);
      expect(pool.connect).not.toHaveBeenCalled();
    },
  );

  it('validates every item and authenticated owner before any connection', async () => {
    const { repository, pool } = fixture();
    await expect(repository.importBatch('bad', input)).rejects.toThrow(
      'invalid_asset_owner',
    );
    await expect(
      repository.importBatch(owner, {
        ...input,
        records: [...input.records, {}],
      }),
    ).rejects.toThrow();
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it('claims receipt and inserts all records on one connection before committing', async () => {
    const { repository, client, pool } = fixture();
    client.query.mockResolvedValueOnce({ rows: [] }).mockResolvedValueOnce({
      rows: [{ request_id: input.requestId }],
      rowCount: 1,
    });
    const result = await repository.importBatch(owner, input);
    expect(result.recordCount).toBe(1);
    expect(result.recordIds[0]).toMatch(/^[0-9a-f-]{36}$/u);
    expect(
      client.query.mock.calls.map(([sql]) => sql.split(/\s+/u)[0]),
    ).toEqual(['BEGIN', 'INSERT', 'INSERT', 'COMMIT']);
    const receiptArgs = client.query.mock.calls[1][1];
    expect(receiptArgs).toEqual([
      owner,
      input.requestId,
      prepareAssetImportV3(input).digest,
      result.recordIds,
    ]);
    const records = JSON.parse(
      client.query.mock.calls[2][1][1] as string,
    ) as unknown;
    expect(records).toEqual([{ ...input.records[0], id: result.recordIds[0] }]);
    expect(pool.query).not.toHaveBeenCalled();
    expect(client.release).toHaveBeenCalledWith(false);
  });

  it('returns original owner-scoped receipt without inserting tools on replay', async () => {
    const { repository, client } = fixture();
    const ids = ['01234567-89ab-4cde-8123-456789abcdef'];
    client.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [{ digest: prepareAssetImportV3(input).digest, recordIds: ids }],
      });
    expect(await repository.importBatch(owner, input)).toEqual({
      requestId: input.requestId,
      recordCount: 1,
      recordIds: ids,
    });
    expect(client.query.mock.calls[2][1]).toEqual([owner, input.requestId]);
    expect(
      client.query.mock.calls.map(([sql]) => sql.split(/\s+/u)[0]),
    ).toEqual(['BEGIN', 'INSERT', 'SELECT', 'COMMIT']);
  });

  it('rolls back changed-content replay and never inserts tools', async () => {
    const { repository, client } = fixture();
    client.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [{ digest: 'different', recordIds: [] }],
      });
    await expect(repository.importBatch(owner, input)).rejects.toThrow(
      ConflictException,
    );
    expect(client.query.mock.calls[3]).toEqual(['ROLLBACK']);
    expect(client.query).toHaveBeenCalledTimes(4);
  });

  it.each([0, 1, 2, 3])(
    'sanitizes failure at statement %i, rolls back, never retries',
    async (failure) => {
      const { repository, client, pool } = fixture();
      for (let i = 0; i < failure; i++)
        client.query.mockResolvedValueOnce({
          rows: [{ request_id: input.requestId }],
          rowCount: 1,
        });
      client.query.mockRejectedValueOnce(new Error('private database details'));
      await expect(repository.importBatch(owner, input)).rejects.toThrow(
        ServiceUnavailableException,
      );
      expect(client.query.mock.calls.at(-1)).toEqual(['ROLLBACK']);
      expect(pool.connect).toHaveBeenCalledTimes(1);
      expect(client.release).toHaveBeenCalledTimes(1);
    },
  );

  it.each([0, null, 2])(
    'rolls back incomplete insert count %s',
    async (rowCount) => {
      const { repository, client } = fixture();
      client.query
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({ rows: [{ request_id: input.requestId }] })
        .mockResolvedValueOnce({ rows: [], rowCount });
      await expect(repository.importBatch(owner, input)).rejects.toThrow(
        ServiceUnavailableException,
      );
      expect(client.query.mock.calls.at(-1)).toEqual(['ROLLBACK']);
      expect(client.query.mock.calls.some(([sql]) => sql === 'COMMIT')).toBe(
        false,
      );
    },
  );

  it.each([
    [],
    ['bad'],
    [null],
    [
      '01234567-89ab-4cde-8123-456789abcdef',
      '01234567-89ab-4cde-8123-456789abcdef',
    ],
  ])('rejects malformed stored receipt IDs %#', async (...values) => {
    const { repository, client } = fixture();
    client.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [
          { digest: prepareAssetImportV3(input).digest, recordIds: values },
        ],
      });
    await expect(repository.importBatch(owner, input)).rejects.toThrow(
      ServiceUnavailableException,
    );
    expect(client.query.mock.calls.at(-1)).toEqual(['ROLLBACK']);
  });

  it('discards a connection when rollback fails', async () => {
    const { repository, client } = fixture();
    client.query
      .mockRejectedValueOnce(new Error('insert failure'))
      .mockRejectedValueOnce(new Error('rollback failure'));
    await expect(repository.importBatch(owner, input)).rejects.toThrow(
      ServiceUnavailableException,
    );
    expect(client.release).toHaveBeenCalledWith(true);
  });

  it('sanitizes connection failure without running a query or attempting release', async () => {
    const { repository, pool, client } = fixture();
    pool.connect.mockRejectedValueOnce(new Error('private connection URL'));
    await expect(repository.importBatch(owner, input)).rejects.toThrow(
      'Import outcome unavailable; retain the same request key',
    );
    expect(client.query).not.toHaveBeenCalled();
    expect(client.release).not.toHaveBeenCalled();
  });
  it('canonicalizes owner before receipt claim and row insertion', async () => {
    const { repository, client } = fixture();
    client.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ request_id: input.requestId }] });
    await repository.importBatch(owner.toUpperCase(), input);
    expect(client.query.mock.calls[1][1][0]).toBe(owner);
    expect(client.query.mock.calls[2][1][0]).toBe(owner);
  });

  it('discards a connection after unknown COMMIT acknowledgement without retry', async () => {
    const { repository, client, pool } = fixture();
    client.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ request_id: input.requestId }] })
      .mockResolvedValueOnce({ rows: [], rowCount: 1 })
      .mockRejectedValueOnce(new Error('lost COMMIT acknowledgement'));
    await expect(repository.importBatch(owner, input)).rejects.toThrow(
      'retain the same request key',
    );
    expect(
      client.query.mock.calls.filter(([sql]) => sql === 'COMMIT'),
    ).toHaveLength(1);
    expect(client.query.mock.calls.at(-1)).toEqual(['ROLLBACK']);
    expect(client.release).toHaveBeenCalledWith(true);
    expect(pool.connect).toHaveBeenCalledTimes(1);
  });

  it('inserts 500 rows as one parameterized statement with independent server IDs', async () => {
    const { repository, client } = fixture();
    client.query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ request_id: input.requestId }] })
      .mockResolvedValueOnce({ rows: [], rowCount: 500 });
    const result = await repository.importBatch(owner, {
      ...input,
      records: Array.from({ length: 500 }, () => ({ ...input.records[0] })),
    });
    expect(new Set(result.recordIds).size).toBe(500);
    const sql = client.query.mock.calls[2][0] as string;
    expect(sql).toContain('jsonb_to_recordset($2::jsonb)');
    expect(sql).not.toContain('Synthetic');
    expect(client.query).toHaveBeenCalledTimes(4);
  });
  it.each(['changed location', 'v2 null location'])(
    'conflicts with %s content on the same owner/key',
    async (scenario) => {
      const { repository, client } = fixture();
      const row = input.records[0];
      const { location: _location, ...old } = row;
      const digest =
        scenario === 'changed location'
          ? prepareAssetImportV3({
              ...input,
              records: [{ ...row, location: 'Other room' }],
            }).digest
          : prepareAssetImportV2({ ...input, records: [old] }).digest;
      client.query
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({ rows: [] })
        .mockResolvedValueOnce({
          rows: [
            { digest, recordIds: ['01234567-89ab-4cde-8123-456789abcdef'] },
          ],
        });
      await expect(repository.importBatch(owner, input)).rejects.toThrow(
        ConflictException,
      );
      expect(
        client.query.mock.calls.map(([sql]) => sql.split(/\s+/u)[0]),
      ).toEqual(['BEGIN', 'INSERT', 'SELECT', 'ROLLBACK']);
    },
  );
});
