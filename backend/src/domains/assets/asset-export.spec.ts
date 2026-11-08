import { createHash } from 'node:crypto';
import {
  UnauthorizedException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { buildAssetExport, ASSET_EXPORT_MAX_BYTES } from './asset-export';
import { AssetsRepository, type AssetRecord } from './assets.repository';
import { AssetsService } from './assets.service';
import { AssetsController } from './assets.controller';

const owner = '507f1f77bcf86cd799439011';
const other = '507f1f77bcf86cd799439012';
const exportedAt = '2026-10-25T08:00:00.000000Z';
const record: AssetRecord = {
  id: '72d9a3cd-3eb1-40ea-ac3f-d549d77ff8da',
  name: 'Synthetic laptop',
  category: 'Laptop',
  serial: '%_1',
  notes: 'Unicode: \u00e9 \u4e2d \ud83d\ude80',
  status: 'stored',
  version: 2,
  createdAt: exportedAt,
  updatedAt: exportedAt,
};

describe('Complete inventory export envelope', () => {
  it.each([0, 1, 51, 500])(
    'exports all %i rows with an exact UTF-8 checksum',
    (count) => {
      const records = Array.from({ length: count }, () => ({ ...record }));
      const before = JSON.stringify(records);
      const envelope = buildAssetExport({ exportedAt, records });
      expect(envelope.format).toBe('asset-desk-inventory');
      expect(envelope.schemaVersion).toBe(1);
      expect(envelope.sha256).toBe(
        createHash('sha256').update(envelope.payload, 'utf8').digest('hex'),
      );
      expect(JSON.parse(envelope.payload)).toEqual({
        exportedAt,
        complete: true,
        recordCount: count,
        records,
      });
      expect(JSON.stringify(records)).toBe(before);
      expect(
        Buffer.byteLength(JSON.stringify(envelope), 'utf8'),
      ).toBeLessThanOrEqual(ASSET_EXPORT_MAX_BYTES);
    },
  );

  it('omits internal and owner fields even if persistence adds them later', () => {
    const internal = {
      ...record,
      owner_id: owner,
      password_hash: 'synthetic',
      future: 'private',
    };
    const envelope = buildAssetExport({ exportedAt, records: [internal] });
    expect(JSON.parse(envelope.payload).records).toEqual([record]);
    expect(envelope.payload).not.toContain('owner_id');
    expect(envelope.payload).not.toContain('password_hash');
    expect(envelope.payload).not.toContain('private');
  });

  it('rejects record overflow rather than exporting the first 500', () => {
    expect(() =>
      buildAssetExport({ exportedAt, records: Array(501).fill(record) }),
    ).toThrow(UnprocessableEntityException);
  });

  it.each(['x', '\u4e2d', '\ud83d\ude80', '\n', '"'])(
    'enforces actual escaped envelope UTF-8 bytes for %j',
    (text) => {
      const records = Array.from({ length: 500 }, () => ({
        ...record,
        notes: text.repeat(2000),
      }));
      expect(() => buildAssetExport({ exportedAt, records })).toThrow(
        UnprocessableEntityException,
      );
    },
  );
});

describe('Snapshot repository and authenticated export delegation', () => {
  function setup() {
    const query = jest
      .fn()
      .mockResolvedValue({ rows: [{ exportedAt, records: [record] }] });
    const repository = new AssetsRepository({ pool: { query } } as never);
    const service = new AssetsService(repository);
    return { query, repository, controller: new AssetsController(service) };
  }

  it('uses one bounded statement snapshot with deterministic owner-only selection', async () => {
    const { query, repository } = setup();
    await expect(repository.snapshot(owner.toUpperCase())).resolves.toEqual({
      exportedAt,
      records: [record],
    });
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, values] = query.mock.calls[0];
    expect(values).toEqual([owner, 501]);
    expect(sql).toContain('statement_timestamp()');
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('ORDER BY updated_at DESC,id DESC LIMIT $2');
    expect(sql).toContain("'[]'::json");
    expect(sql).not.toMatch(/OFFSET|INSERT|UPDATE|DELETE|CREATE|ALTER|BEGIN/);
    expect(sql).not.toContain(owner);
  });

  it('takes identity only from authentication and binds each owner separately', async () => {
    const { query, controller } = setup();
    await controller.exportInventory({ user: { userId: owner } });
    await controller.exportInventory({ user: { userId: other } });
    expect(query.mock.calls.map((call) => call[1][0])).toEqual([owner, other]);
    for (const request of [{}, { user: { userId: 'bad' } }]) {
      expect(() => controller.exportInventory(request)).toThrow(
        UnauthorizedException,
      );
    }
    expect(query).toHaveBeenCalledTimes(2);
  });

  it('refuses invalid repository identity before any database access', async () => {
    const { query, repository } = setup();
    await expect(repository.snapshot('invalid')).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).not.toHaveBeenCalled();
  });

  it('propagates missing data and storage failure without retry', async () => {
    const { query, repository } = setup();
    query.mockResolvedValueOnce({ rows: [] });
    await expect(repository.snapshot(owner)).rejects.toThrow(
      'asset_snapshot_missing',
    );
    query.mockRejectedValueOnce(new Error('synthetic storage failure'));
    await expect(repository.snapshot(owner)).rejects.toThrow(
      'synthetic storage failure',
    );
    expect(query).toHaveBeenCalledTimes(2);
  });
});
