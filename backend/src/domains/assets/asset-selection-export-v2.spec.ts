import { createHash } from 'node:crypto';
import type { AssetSelectionScope } from './asset-selection-export';
import {
  buildAssetSelectionExportV2,
  validateSelectionCheck,
} from './asset-selection-export-v2';

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

describe('selection v2 manual check contract', () => {
  const snapshot = (date: string | null = null) => ({
    exportedAt: record.createdAt,
    records: [{ ...record, lastCheckedDate: date, ownerId: 'private' }],
  });
  it.each(['all', 'unknown'] as const)('supports %s without cutoff', (mode) => {
    const input = snapshot();
    const before = JSON.stringify(input);
    const result = buildAssetSelectionExportV2(input, {
      ...scope,
      check: { mode },
    });
    const body = JSON.parse(result.payload);
    expect(result.schemaVersion).toBe(2);
    expect(body.records[0].lastCheckedDate).toBeNull();
    expect(body.filters.check).toEqual({ mode });
    expect(body).not.toHaveProperty('complete');
    expect(result.payload).not.toContain('ownerId');
    expect(result.sha256).toBe(
      createHash('sha256').update(result.payload, 'utf8').digest('hex'),
    );
    expect(JSON.stringify(input)).toBe(before);
  });
  it.each([
    ['before', '2024-03-01', '2024-02-29'],
    ['on_or_after', '2024-02-29', '2024-02-29'],
    ['on_or_after', '0001-01-01', '9999-12-31'],
  ] as const)('accepts %s calendar boundaries', (mode, cutoff, date) => {
    expect(
      JSON.parse(
        buildAssetSelectionExportV2(snapshot(date), {
          ...scope,
          check: { mode, cutoff },
        }).payload,
      ).records[0].lastCheckedDate,
    ).toBe(date);
  });
  it.each([
    null,
    [],
    {},
    { mode: 'unchecked' },
    { mode: 'all', cutoff: '2024-01-01' },
    { mode: 'unknown', extra: true },
    { mode: 'before' },
    { mode: 'before', cutoff: '2023-02-29' },
    { mode: 'before', cutoff: '0000-01-01' },
    { mode: 'on_or_after', cutoff: '2024-02-29T00:00:00Z' },
  ])('rejects ambiguous check filter %j', (value) =>
    expect(() => validateSelectionCheck(value)).toThrow(),
  );
  it.each([
    ['unknown', '2024-02-29'],
    ['before', '2024-03-01'],
    ['on_or_after', '2024-02-29'],
  ] as const)('rejects snapshot outside %s scope', (mode, date) => {
    const check =
      mode === 'unknown' ? { mode } : { mode, cutoff: '2024-03-01' };
    expect(() =>
      buildAssetSelectionExportV2(snapshot(date), { ...scope, check }),
    ).toThrow('scope_mismatch');
  });
  it('rejects missing/invalid dates and extra scope keys', () => {
    expect(() =>
      buildAssetSelectionExportV2(snapshot('2023-02-29'), {
        ...scope,
        check: { mode: 'all' },
      }),
    ).toThrow();
    expect(() =>
      buildAssetSelectionExportV2(snapshot(), {
        ...scope,
        check: { mode: 'all' },
        extra: true,
      } as never),
    ).toThrow();
  });
  it.each([0, 500, 501])('bounds %i records without truncation', (count) => {
    const run = () =>
      buildAssetSelectionExportV2(
        {
          exportedAt: record.createdAt,
          records: Array(count).fill({ ...record, lastCheckedDate: null }),
        },
        { ...scope, check: { mode: 'all' } },
      );
    if (count > 500) expect(run).toThrow('500');
    else expect(JSON.parse(run().payload).recordCount).toBe(count);
  });
  it.each(['before', 'on_or_after'] as const)(
    'rejects unknown dates in %s results',
    (mode) => {
      expect(() =>
        buildAssetSelectionExportV2(snapshot(), {
          ...scope,
          check: { mode, cutoff: '2024-03-01' },
        }),
      ).toThrow('scope_mismatch');
    },
  );
  it('does not coerce an absent check date to null', () => {
    const input = { exportedAt: record.createdAt, records: [{ ...record }] };
    expect(() =>
      buildAssetSelectionExportV2(input as never, {
        ...scope,
        check: { mode: 'all' },
      }),
    ).toThrow('invalid_selection_check_date');
  });
  it('counts escaped UTF-8 bytes of the final envelope, not characters', () => {
    const make = (length: number) =>
      buildAssetSelectionExportV2(
        {
          exportedAt: record.createdAt,
          records: Array(200).fill({
            ...record,
            notes: '\u754c'.repeat(length),
            lastCheckedDate: '2024-02-29',
          }),
        },
        { ...scope, check: { mode: 'all' } },
      );
    expect(
      Buffer.byteLength(JSON.stringify(make(1000)), 'utf8'),
    ).toBeLessThanOrEqual(1024 * 1024);
    expect(() => make(2000)).toThrow('1 MiB');
  });
  it('preserves a combined explicit warranty reference without changing input', () => {
    const combined = {
      ...scope,
      warranty: {
        filter: 'expiring_soon' as const,
        asOf: '2026-10-29',
        through: '2026-11-28',
      },
      check: { mode: 'before' as const, cutoff: '2024-03-01' },
    };
    const original = JSON.stringify(combined);
    const body = JSON.parse(
      buildAssetSelectionExportV2(snapshot('2024-02-29'), combined).payload,
    );
    expect(body.filters).toEqual(combined);
    expect(JSON.stringify(combined)).toBe(original);
  });
});
