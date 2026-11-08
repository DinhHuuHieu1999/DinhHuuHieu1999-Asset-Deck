import { createHash } from 'node:crypto';
import { prepareAssetImportV4 } from './asset-import-v4';
import { prepareAssetImportV3 } from './asset-import-v3';

const requestId = '00000000-0000-4000-8000-000000000001';
const row = {
  name: 'Laptop',
  category: 'fixture',
  serial: 'NATIVE-%_1',
  status: 'stored',
  notes: '',
  purchasedOn: null,
  warrantyExpiresOn: null,
  location: null,
  lastCheckedDate: '2024-02-29',
};
const request = () => ({ requestId, records: [{ ...row }] });
describe('pure import v4', () => {
  it('uses independently constructed v4 canonical bytes and freezes records', () => {
    const input = request();
    const result = prepareAssetImportV4(input);
    expect(result.digest).toBe(
      createHash('sha256')
        .update(
          JSON.stringify({
            format: 'asset-desk-inventory-add-only',
            schemaVersion: 4,
            records: [row],
          }),
          'utf8',
        )
        .digest('hex'),
    );
    expect(Object.isFrozen(result)).toBe(true);
    expect(Object.isFrozen(result.records)).toBe(true);
    expect(Object.isFrozen(result.records[0])).toBe(true);
    input.records[0].lastCheckedDate = '2024-03-01';
    expect(result.records[0].lastCheckedDate).toBe('2024-02-29');
  });
  it.each([null, '0001-01-01', '9999-12-31'])(
    'preserves literal date %s without a current-day dependency',
    (date) => {
      expect(
        prepareAssetImportV4({
          requestId,
          records: [{ ...row, lastCheckedDate: date }],
        }).records[0].lastCheckedDate,
      ).toBe(date);
    },
  );
  it.each(['2023-02-29', '0000-01-01', '2024-02-30', '', undefined, 42])(
    'rejects invalid date %s',
    (date) => {
      expect(() =>
        prepareAssetImportV4({
          requestId,
          records: [{ ...row, lastCheckedDate: date }],
        }),
      ).toThrow();
    },
  );
  it('rejects missing or extra fields and old requests', () => {
    const { lastCheckedDate: _date, ...v3 } = row;
    expect(() => prepareAssetImportV4({ requestId, records: [v3] })).toThrow();
    expect(() =>
      prepareAssetImportV4({
        requestId,
        records: [{ ...row, ownerId: 'other' }],
      }),
    ).toThrow();
    expect(() => prepareAssetImportV3(request())).toThrow();
    expect(prepareAssetImportV3({ requestId, records: [v3] }).digest).not.toBe(
      prepareAssetImportV4(request()).digest,
    );
  });
  it('binds manual dates and record order, not request ID, to the digest', () => {
    const original = prepareAssetImportV4(request());
    expect(
      prepareAssetImportV4({
        requestId,
        records: [{ ...row, lastCheckedDate: null }],
      }).digest,
    ).not.toBe(original.digest);
    expect(
      prepareAssetImportV4({
        ...request(),
        requestId: '00000000-0000-4000-8000-000000000002',
      }).digest,
    ).toBe(original.digest);
    const records = [row, { ...row, name: 'Second' }];
    expect(prepareAssetImportV4({ requestId, records }).digest).not.toBe(
      prepareAssetImportV4({ requestId, records: [...records].reverse() })
        .digest,
    );
  });
  it('rejects 501 records', () => {
    expect(() =>
      prepareAssetImportV4({
        requestId,
        records: Array.from({ length: 501 }, () => ({ ...row })),
      }),
    ).toThrow();
  });
});

describe('v4 preparation boundaries', () => {
  it('accepts 500 records and preserves nullable check dates', () => {
    const result = prepareAssetImportV4({
      requestId,
      records: Array.from({ length: 500 }, () => ({
        ...row,
        lastCheckedDate: null,
      })),
    });
    expect(result.records).toHaveLength(500);
    expect(
      result.records.every((record) => record.lastCheckedDate === null),
    ).toBe(true);
  });
  it.each([
    null,
    [],
    {},
    { requestId, records: [] },
    { requestId, records: 'bad' },
    { requestId, records: [row], owner: 'other' },
  ])('refuses malformed or empty request %#', (value) => {
    expect(() => prepareAssetImportV4(value)).toThrow();
  });
  it.each([
    'name',
    'category',
    'serial',
    'notes',
    'location',
    'purchasedOn',
    'warrantyExpiresOn',
  ])('binds changed %s to its digest', (field) => {
    const value =
      field === 'purchasedOn'
        ? '2024-01-01'
        : field === 'warrantyExpiresOn'
          ? '2028-01-01'
          : 'Changed';
    expect(
      prepareAssetImportV4({ requestId, records: [{ ...row, [field]: value }] })
        .digest,
    ).not.toBe(prepareAssetImportV4(request()).digest);
  });
  it('rejects total request overflow independently of per-field limits', () => {
    const large = { ...row, notes: '\u754c'.repeat(1000) };
    expect(() =>
      prepareAssetImportV4({
        requestId,
        records: Array.from({ length: 500 }, () => ({ ...large })),
      }),
    ).toThrow();
  });
});
