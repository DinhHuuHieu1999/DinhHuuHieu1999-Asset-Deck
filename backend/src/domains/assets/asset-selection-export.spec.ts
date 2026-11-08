import { createHash } from 'node:crypto';
import {
  buildAssetSelectionExport,
  validateAssetSelectionScope,
  type AssetSelectionScope,
} from './asset-selection-export';

const scope: AssetSelectionScope = {
  q: '%_',
  status: 'stored',
  category: '',
  locationMode: 'exact',
  location: 'Room %_1',
  sort: 'name_asc',
  warranty: null,
};
const record = {
  id: '72d9a3cd-3eb1-40ea-ac3f-d549d77ff8da',
  name: 'Synthetic',
  category: 'fixture',
  serial: '%_1',
  status: 'stored' as const,
  notes: '',
  version: 1,
  createdAt: '2026-10-27T08:00:00.000Z',
  updatedAt: '2026-10-27T08:00:00.000Z',
  purchasedOn: '2024-02-29',
  warrantyExpiresOn: '2027-02-28',
  location: 'Room %_1',
};

describe('filtered selection export contract', () => {
  it.each([0, 1, 51, 500])(
    'serializes all %i matches with a distinct envelope',
    (count) => {
      const input = {
        exportedAt: record.createdAt,
        records: Array.from({ length: count }, () => ({
          ...record,
          ownerId: 'private',
        })),
      };
      const before = JSON.stringify(input);
      const result = buildAssetSelectionExport(input, scope);
      const payload = JSON.parse(result.payload);
      expect(result.format).toBe('asset-desk-inventory-selection');
      expect(result.schemaVersion).toBe(1);
      expect(payload).not.toHaveProperty('complete');
      expect(payload.scope).toBe('filtered-selection');
      expect(payload.allMatchesIncluded).toBe(true);
      expect(payload.recordCount).toBe(count);
      expect(payload.records).toHaveLength(count);
      expect(payload.filters).toEqual(scope);
      expect(result.payload).not.toContain('ownerId');
      expect(result.sha256).toBe(
        createHash('sha256').update(result.payload, 'utf8').digest('hex'),
      );
      expect(JSON.stringify(input)).toBe(before);
    },
  );
  it('rejects 501 matches, not truncating', () => {
    expect(() =>
      buildAssetSelectionExport(
        { exportedAt: record.createdAt, records: Array(501).fill(record) },
        scope,
      ),
    ).toThrow('500');
  });
  it.each([
    { q: ' x ' },
    { q: 'x'.repeat(121) },
    { status: 'invalid' },
    { sort: 'name;DROP' },
    { sort: undefined },
    { locationMode: 'unknown' },
    { locationMode: 'exact', location: null },
    { warranty: { filter: 'expired', asOf: '', through: '2026-11-01' } },
    {
      warranty: {
        filter: 'expired',
        asOf: '2026-10-29',
        through: '2026-10-30',
      },
    },
  ])('rejects ambiguous metadata %j', (patch) => {
    expect(() =>
      validateAssetSelectionScope({
        ...scope,
        ...patch,
      } as AssetSelectionScope),
    ).toThrow();
  });
  it('keeps exact reference date and canonical unknown location', () => {
    const value = {
      ...scope,
      locationMode: 'unknown' as const,
      location: null,
      warranty: {
        filter: 'expiring_soon' as const,
        asOf: '2026-10-29',
        through: '2026-11-28',
      },
    };
    expect(validateAssetSelectionScope(value)).toEqual(value);
  });
});
