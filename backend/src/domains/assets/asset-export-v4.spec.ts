import { buildAssetExportV3 } from './asset-export-v3';
import { isAssetExportV4Enabled } from './asset-export-v4.config';
import { AssetExportV4Controller } from './asset-export-v4.controller';
import { createHash } from 'node:crypto';
import { buildAssetExport } from './asset-export';
import { buildAssetExportV2 } from './asset-export-v2';
import {
  buildAssetExportV4,
  type AssetExportV4Record,
} from './asset-export-v4';

const exportedAt = '2026-10-27T08:00:00.000Z';
const record: AssetExportV4Record = {
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
  lastCheckedDate: '2024-03-01',
};

describe('Location-aware inventory export v4', () => {
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
      const result = buildAssetExportV4(snapshot);
      expect(result.schemaVersion).toBe(4);
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
      JSON.parse(buildAssetExportV4(snapshot).payload).records[0].location,
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
        buildAssetExportV4({
          exportedAt,
          records: [{ ...record, location } as AssetExportV4Record],
        }),
      ).toThrow();
    },
  );
  it('rejects a v4 envelope that exceeds the byte limit after adding locations', () => {
    const records = Array.from({ length: 500 }, () => ({
      ...record,
      notes: 'n'.repeat(1600),
      location: '\u754c'.repeat(120),
    }));
    // The old schema fits; only the location-aware envelope crosses the limit.
    expect(() => buildAssetExportV2({ exportedAt, records })).not.toThrow();
    expect(() => buildAssetExportV4({ exportedAt, records })).toThrow(
      'Inventory export exceeds 1 MiB',
    );
  });
  it('refuses partial exports over 500 rows', () => {
    expect(() =>
      buildAssetExportV4({ exportedAt, records: Array(501).fill(record) }),
    ).toThrow();
  });
});

describe('v4 controller and opt-in configuration', () => {
  it('defaults off and rejects invalid or missing capability flags', () => {
    expect(isAssetExportV4Enabled({})).toBe(false);
    for (const value of ['TRUE', '1', '']) {
      expect(() =>
        isAssetExportV4Enabled({ ASSET_EXPORT_V4_ENABLED: value }),
      ).toThrow();
    }
    expect(() =>
      isAssetExportV4Enabled({ ASSET_EXPORT_V4_ENABLED: 'true' }),
    ).toThrow();
    expect(
      isAssetExportV4Enabled({
        ASSET_EXPORT_V4_ENABLED: 'true',
        ASSET_CHECK_ENABLED: 'true',
        ASSET_DATES_ENABLED: 'true',
        ASSET_LOCATION_ENABLED: 'true',
      }),
    ).toBe(true);
  });
  it('rejects anonymous owners and filters before repository access', async () => {
    const repository = { exportSnapshot: jest.fn() };
    const controller = new AssetExportV4Controller(repository as never);
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
    const controller = new AssetExportV4Controller(repository as never);
    expect(
      (
        await controller.exportInventory(
          { user: { userId: '507f1f77bcf86cd799439011' } },
          {},
        )
      ).schemaVersion,
    ).toBe(4);
    expect(repository.exportSnapshot).toHaveBeenCalledWith(
      '507f1f77bcf86cd799439011',
    );
  });
});

describe('v4 manual check boundaries', () => {
  it.each([null, '0001-01-01', '2024-02-29', '9999-12-31'])(
    'preserves explicit check date %p',
    (lastCheckedDate) => {
      const value = buildAssetExportV4({
        exportedAt,
        records: [{ ...record, lastCheckedDate }],
      });
      expect(JSON.parse(value.payload).records[0].lastCheckedDate).toBe(
        lastCheckedDate,
      );
    },
  );
  it.each([
    undefined,
    '',
    '2023-02-29',
    '2024-02-30',
    '0000-01-01',
    '2024-01-01T00:00:00Z',
    1,
  ])('rejects malformed or missing check date %p', (lastCheckedDate) => {
    expect(() =>
      buildAssetExportV4({
        exportedAt,
        records: [{ ...record, lastCheckedDate } as AssetExportV4Record],
      }),
    ).toThrow();
  });
});

describe('v4 compatibility and final envelope boundary', () => {
  it('keeps v3 free of manual check fields', () => {
    const payload = JSON.parse(
      buildAssetExportV3({ exportedAt, records: [record] }).payload,
    );
    expect(payload.records[0]).not.toHaveProperty('lastCheckedDate');
    expect(payload.records[0].location).toBe(record.location);
  });
  it('refuses overflow introduced only by check dates', () => {
    let low = 0,
      high = 2000;
    const rows = (length: number) =>
      Array.from({ length: 500 }, () => ({
        ...record,
        notes: 'n'.repeat(length),
      }));
    while (low < high) {
      const mid = Math.ceil((low + high) / 2);
      try {
        buildAssetExportV3({ exportedAt, records: rows(mid) });
        low = mid;
      } catch {
        high = mid - 1;
      }
    }
    expect(() =>
      buildAssetExportV3({ exportedAt, records: rows(low) }),
    ).not.toThrow();
    expect(() =>
      buildAssetExportV4({ exportedAt, records: rows(low) }),
    ).toThrow('Inventory export exceeds 1 MiB');
  });
  it.each([
    'ASSET_DATES_ENABLED',
    'ASSET_LOCATION_ENABLED',
    'ASSET_CHECK_ENABLED',
  ])('refuses missing required capability %s', (key) => {
    const env: NodeJS.ProcessEnv = {
      ASSET_EXPORT_V4_ENABLED: 'true',
      ASSET_DATES_ENABLED: 'true',
      ASSET_LOCATION_ENABLED: 'true',
      ASSET_CHECK_ENABLED: 'true',
    };
    delete env[key];
    expect(() => isAssetExportV4Enabled(env)).toThrow();
  });
});
