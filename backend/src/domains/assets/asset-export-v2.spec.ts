import { createHash } from 'node:crypto';
import {
  BadRequestException,
  UnauthorizedException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { buildAssetExport } from './asset-export';
import {
  buildAssetExportV2,
  type AssetExportV2Record,
} from './asset-export-v2';
import { AssetExportV2Controller } from './asset-export-v2.controller';
import { AssetDatesRepository } from './asset-dates.repository';

const owner = '507f1f77bcf86cd799439011';
const exportedAt = '2026-10-26T08:00:00.000000Z';
const record: AssetExportV2Record = {
  id: '72d9a3cd-3eb1-40ea-ac3f-d549d77ff8da',
  name: 'Synthetic',
  category: 'Laptop',
  serial: '%_1',
  status: 'stored',
  notes: '\u4e2d',
  version: 2147483647,
  createdAt: exportedAt,
  updatedAt: exportedAt,
  purchasedOn: '2024-02-29',
  warrantyExpiresOn: '2026-10-26',
};

describe('Date-aware export v2', () => {
  it.each([0, 1, 51, 500])(
    'exports %i complete records with exact payload checksum',
    (count) => {
      const rows = Array.from({ length: count }, () => ({ ...record }));
      const before = JSON.stringify(rows);
      const result = buildAssetExportV2({ exportedAt, records: rows });
      expect(result.schemaVersion).toBe(2);
      expect(result.format).toBe('asset-desk-inventory');
      expect(JSON.parse(result.payload)).toEqual({
        exportedAt,
        complete: true,
        recordCount: count,
        records: rows,
      });
      expect(result.sha256).toBe(
        createHash('sha256').update(result.payload, 'utf8').digest('hex'),
      );
      expect(JSON.stringify(rows)).toBe(before);
    },
  );
  it.each([
    [null, null],
    [null, '9999-12-31'],
    ['0001-01-01', null],
    ['2024-02-29', '2024-02-29'],
  ])(
    'preserves nullable calendar dates %j %j',
    (purchasedOn, warrantyExpiresOn) => {
      const result = buildAssetExportV2({
        exportedAt,
        records: [{ ...record, purchasedOn, warrantyExpiresOn }],
      });
      expect(JSON.parse(result.payload).records[0]).toEqual({
        ...record,
        purchasedOn,
        warrantyExpiresOn,
      });
    },
  );
  it.each(['2023-02-29', '0000-01-01', '2024-01-01T00:00:00Z', undefined])(
    'refuses malformed/missing date %j',
    (purchasedOn) => {
      expect(() =>
        buildAssetExportV2({
          exportedAt,
          records: [{ ...record, purchasedOn } as AssetExportV2Record],
        }),
      ).toThrow('invalid_asset_export_dates');
    },
  );
  it('refuses reversed dates', () => {
    expect(() =>
      buildAssetExportV2({
        exportedAt,
        records: [{ ...record, warrantyExpiresOn: '2020-01-01' }],
      }),
    ).toThrow('invalid_asset_export_dates');
  });
  it('projects public fields and leaves v1 unchanged', () => {
    const internal = { ...record, owner_id: owner, future: 'private' };
    const v2 = JSON.parse(
      buildAssetExportV2({ exportedAt, records: [internal] }).payload,
    ).records[0];
    expect(v2).toEqual(record);
    const v1 = buildAssetExport({ exportedAt, records: [internal] });
    expect(v1.schemaVersion).toBe(1);
    expect(JSON.parse(v1.payload).records[0]).not.toHaveProperty('purchasedOn');
    expect(JSON.parse(v1.payload).records[0]).not.toHaveProperty(
      'warrantyExpiresOn',
    );
  });
  it('refuses record and byte overflow without partial output', () => {
    expect(() =>
      buildAssetExportV2({ exportedAt, records: Array(501).fill(record) }),
    ).toThrow(UnprocessableEntityException);
    expect(() =>
      buildAssetExportV2({
        exportedAt,
        records: Array(500).fill({ ...record, notes: 'x'.repeat(2200) }),
      }),
    ).toThrow(UnprocessableEntityException);
  });
  it('uses one bounded SQL statement for base fields, version and dates', async () => {
    const snapshot = { exportedAt, records: [record] };
    const query = jest.fn().mockResolvedValue({ rows: [snapshot] });
    const repository = new AssetDatesRepository({ pool: { query } } as never);
    expect(await repository.exportSnapshot(owner.toUpperCase())).toEqual(
      snapshot,
    );
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, parameters] = query.mock.calls[0];
    expect(parameters).toEqual([owner, 501]);
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('ORDER BY updated_at DESC,id DESC LIMIT $2');
    expect(sql).toContain('purchased_on');
    expect(sql).toContain('warranty_expires_on');
    expect(sql).not.toContain('SELECT *');
    await expect(repository.exportSnapshot('invalid')).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('refuses missing repository snapshot', async () => {
    const repository = new AssetDatesRepository({
      pool: { query: jest.fn().mockResolvedValue({ rows: [] }) },
    } as never);
    await expect(repository.exportSnapshot(owner)).rejects.toThrow(
      'asset_snapshot_missing',
    );
  });
  it('rejects missing auth and all query inputs before persistence', async () => {
    const exportSnapshot = jest
      .fn()
      .mockResolvedValue({ exportedAt, records: [record] });
    const controller = new AssetExportV2Controller({ exportSnapshot } as never);
    await expect(controller.exportInventory({}, {})).rejects.toThrow(
      UnauthorizedException,
    );
    await expect(
      controller.exportInventory(
        { user: { userId: owner } },
        { owner: 'other' },
      ),
    ).rejects.toThrow(BadRequestException);
    expect(exportSnapshot).not.toHaveBeenCalled();
    const result = await controller.exportInventory(
      { user: { userId: owner } },
      {},
    );
    expect(result.schemaVersion).toBe(2);
    expect(exportSnapshot).toHaveBeenCalledWith(owner);
  });
});
