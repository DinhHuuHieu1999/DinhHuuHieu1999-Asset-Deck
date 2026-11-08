import { isAssetExportV3Enabled } from './asset-export-v3.config';
import { AssetExportV3Controller } from './asset-export-v3.controller';
import { createHash } from 'node:crypto';
import { buildAssetExport } from './asset-export';
import { buildAssetExportV2 } from './asset-export-v2';
import {
  buildAssetExportV3,
  type AssetExportV3Record,
} from './asset-export-v3';

const exportedAt = '2026-10-27T08:00:00.000Z';
const record: AssetExportV3Record = {
  id: '72d9a3cd-3eb1-40ea-ac3f-d549d77ff8da',
  name: 'Synthetic',
  category: 'fixture',
  serial: '%_1',
  status: 'stored',
  notes: '',
  version: 1,
  createdAt: exportedAt,
  updatedAt: exportedAt,
  purchasedOn: '2024-02-29',
  warrantyExpiresOn: '2027-02-28',
  location: 'Room %_1',
};

describe('Location-aware inventory export v3', () => {
  it.each([0, 1, 51, 500])(
    'exports %i complete rows without mutating input',
    (count) => {
      const snapshot = {
        exportedAt,
        records: Array.from({ length: count }, () => ({
          ...record,
          ownerId: 'private',
        })),
      };
      const before = JSON.stringify(snapshot);
      const result = buildAssetExportV3(snapshot);
      expect(result.schemaVersion).toBe(3);
      const payload = JSON.parse(result.payload);
      expect(payload.complete).toBe(true);
      expect(payload.recordCount).toBe(count);
      expect(payload.records).toEqual(
        Array.from({ length: count }, () => record),
      );
      expect(result.sha256).toBe(
        createHash('sha256').update(result.payload, 'utf8').digest('hex'),
      );
      expect(JSON.stringify(snapshot)).toBe(before);
    },
  );
  it('keeps null locations and old schemas unchanged', () => {
    const snapshot = { exportedAt, records: [{ ...record, location: null }] };
    expect(
      JSON.parse(buildAssetExportV3(snapshot).payload).records[0].location,
    ).toBeNull();
    for (const result of [
      buildAssetExport(snapshot),
      buildAssetExportV2(snapshot),
    ]) {
      expect(JSON.parse(result.payload).records[0]).not.toHaveProperty(
        'location',
      );
    }
  });
  it.each(['', ' room ', 'x'.repeat(121), 'a\nb', '\ud800', undefined])(
    'rejects invalid/noncanonical location %p',
    (location) => {
      expect(() =>
        buildAssetExportV3({
          exportedAt,
          records: [{ ...record, location } as AssetExportV3Record],
        }),
      ).toThrow();
    },
  );
  it('rejects a v3 envelope that exceeds the byte limit after adding locations', () => {
    const records = Array.from({ length: 500 }, () => ({
      ...record,
      notes: 'n'.repeat(1600),
      location: '\u754c'.repeat(120),
    }));
    // The old schema fits; only the location-aware envelope crosses the limit.
    expect(() => buildAssetExportV2({ exportedAt, records })).not.toThrow();
    expect(() => buildAssetExportV3({ exportedAt, records })).toThrow(
      'Inventory export exceeds 1 MiB',
    );
  });
  it('refuses partial exports over 500 rows', () => {
    expect(() =>
      buildAssetExportV3({ exportedAt, records: Array(501).fill(record) }),
    ).toThrow();
  });
});

describe('v3 controller and opt-in configuration', () => {
  it('defaults off and rejects invalid or missing capability flags', () => {
    expect(isAssetExportV3Enabled({})).toBe(false);
    for (const value of ['TRUE', '1', '']) {
      expect(() =>
        isAssetExportV3Enabled({ ASSET_EXPORT_V3_ENABLED: value }),
      ).toThrow();
    }
    expect(() =>
      isAssetExportV3Enabled({ ASSET_EXPORT_V3_ENABLED: 'true' }),
    ).toThrow();
    expect(
      isAssetExportV3Enabled({
        ASSET_EXPORT_V3_ENABLED: 'true',
        ASSET_DATES_ENABLED: 'true',
        ASSET_LOCATION_ENABLED: 'true',
      }),
    ).toBe(true);
  });
  it('rejects anonymous owners and filters before repository access', async () => {
    const repository = { exportSnapshot: jest.fn() };
    const controller = new AssetExportV3Controller(repository as never);
    await expect(controller.exportInventory({}, {})).rejects.toThrow();
    await expect(
      controller.exportInventory(
        { user: { userId: '507f1f77bcf86cd799439011' } },
        { q: 'filtered' },
      ),
    ).rejects.toThrow();
    expect(repository.exportSnapshot).not.toHaveBeenCalled();
  });
  it('serializes the complete authenticated owner snapshot', async () => {
    const repository = {
      exportSnapshot: jest
        .fn()
        .mockResolvedValue({ exportedAt, records: [record] }),
    };
    const controller = new AssetExportV3Controller(repository as never);
    expect(
      (
        await controller.exportInventory(
          { user: { userId: '507f1f77bcf86cd799439011' } },
          {},
        )
      ).schemaVersion,
    ).toBe(3);
    expect(repository.exportSnapshot).toHaveBeenCalledWith(
      '507f1f77bcf86cd799439011',
    );
  });
});
