import { prepareAssetImportV2 } from './asset-import-v2';
import { PayloadTooLargeException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { ASSET_IMPORT_MAX_BYTES, prepareAssetImport } from './asset-import';
import { prepareAssetImportV3 } from './asset-import-v3';

const requestId = '00000000-0000-4000-8000-000000000001';
const base = {
  name: ' Laptop ',
  category: 'Computer',
  serial: '',
  status: 'stored',
  notes: '',
};
const row = {
  ...base,
  purchasedOn: null,
  warrantyExpiresOn: null,
  location: null,
};
const request = () => ({ requestId, records: [{ ...row }] });

describe('pure import v3 preparation', () => {
  it('matches independently constructed canonical bytes and includes record order', () => {
    const records = [
      { ...row, name: 'First', purchasedOn: '2024-02-29' },
      { ...row, name: 'Second', warrantyExpiresOn: '2028-01-01' },
    ];
    const result = prepareAssetImportV3({ requestId, records });
    const canonical = JSON.stringify({
      format: 'asset-desk-inventory-add-only',
      schemaVersion: 3,
      records,
    });
    expect(result.digest).toBe(
      createHash('sha256').update(canonical, 'utf8').digest('hex'),
    );
    expect(
      prepareAssetImportV3({ requestId, records: [...records].reverse() })
        .digest,
    ).not.toBe(result.digest);
    expect(
      prepareAssetImportV3({
        requestId,
        records: [
          records[0],
          { ...records[1], warrantyExpiresOn: '2028-01-02' },
        ],
      }).digest,
    ).not.toBe(result.digest);
  });
  it('accepts exactly 1 MiB and rejects one more byte including date fields', () => {
    const records = Array.from({ length: 500 }, () => ({
      ...row,
      purchasedOn: '0001-01-01',
      warrantyExpiresOn: '9999-12-31',
      notes: '',
    }));
    const input = { requestId, records };
    let remaining =
      ASSET_IMPORT_MAX_BYTES - Buffer.byteLength(JSON.stringify(input));
    // Three-byte BMP characters keep the existing 2,000-character field cap.
    for (const record of records) {
      const count = Math.min(1999, Math.floor(remaining / 3));
      record.notes = '\u4e2d'.repeat(count);
      remaining -= count * 3;
    }
    records[499].notes += 'a'.repeat(remaining);
    expect(Buffer.byteLength(JSON.stringify(input))).toBe(
      ASSET_IMPORT_MAX_BYTES,
    );
    expect(prepareAssetImportV3(input).records).toHaveLength(500);
    records[499].notes += 'a';
    expect(() => prepareAssetImportV3(input)).toThrow(PayloadTooLargeException);
  });
  it('normalizes, copies and deeply freezes records', () => {
    const input = request();
    const result = prepareAssetImportV3(input);
    input.records[0].name = 'Changed';
    expect(result.records[0].name).toBe('Laptop');
    expect(Object.isFrozen(result)).toBe(true);
    expect(Object.isFrozen(result.records)).toBe(true);
    expect(Object.isFrozen(result.records[0])).toBe(true);
  });
  it('separates v1 and v3 digests, including explicit unknown dates', () => {
    expect(prepareAssetImportV3(request()).digest).not.toBe(
      prepareAssetImport({ requestId, records: [base] }).digest,
    );
  });
  it('ignores property order and request key but includes dates', () => {
    const first = prepareAssetImportV3(request());
    const reordered = Object.fromEntries(Object.entries(row).reverse());
    expect(
      prepareAssetImportV3({
        records: [reordered],
        requestId: '00000000-0000-4000-8000-000000000002',
      }).digest,
    ).toBe(first.digest);
    expect(
      prepareAssetImportV3({
        requestId,
        records: [{ ...row, purchasedOn: '2024-02-29' }],
      }).digest,
    ).not.toBe(first.digest);
  });
  it.each([
    '0000-01-01',
    '2023-02-29',
    '1900-02-29',
    '2024-04-31',
    '2024-01-01 ',
    '2024-01-01T00:00:00Z',
  ])('rejects invalid date %s', (purchasedOn) => {
    expect(() =>
      prepareAssetImportV3({ requestId, records: [{ ...row, purchasedOn }] }),
    ).toThrow();
  });
  it.each(['0001-01-01', '2000-02-29', '9999-12-31'])(
    'accepts calendar boundary %s',
    (purchasedOn) => {
      expect(
        prepareAssetImportV3({ requestId, records: [{ ...row, purchasedOn }] })
          .records[0].purchasedOn,
      ).toBe(purchasedOn);
    },
  );
  it('rejects reversed dates, missing dates and extra metadata', () => {
    for (const record of [
      base,
      { ...row, version: 1 },
      { ...row, purchasedOn: '2026-01-02', warrantyExpiresOn: '2026-01-01' },
    ]) {
      expect(() =>
        prepareAssetImportV3({ requestId, records: [record] }),
      ).toThrow();
    }
  });
  it('retains existing count, Unicode and base-field validation', () => {
    for (const records of [
      [],
      Array(501).fill(row),
      [{ ...row, notes: '\ud800' }],
      [{ ...row, status: 'invalid' }],
    ]) {
      expect(() => prepareAssetImportV3({ requestId, records })).toThrow();
    }
    expect(
      prepareAssetImportV3({ requestId, records: Array(500).fill(row) })
        .records,
    ).toHaveLength(500);
  });
  it('canonicalizes location and includes it in the v3 digest', () => {
    const a = prepareAssetImportV3({
      requestId,
      records: [{ ...row, location: ' Room %_1 ' }],
    });
    const b = prepareAssetImportV3({
      requestId,
      records: [{ ...row, location: 'Room %_1' }],
    });
    expect(a.records[0].location).toBe('Room %_1');
    expect(a.digest).toBe(b.digest);
    expect(a.digest).not.toBe(prepareAssetImportV3(request()).digest);
  });
  it.each(['', ' ', 'a'.repeat(121), 'a\nb', '\ud800', 123, false])(
    'rejects invalid location %j',
    (location) => {
      expect(() =>
        prepareAssetImportV3({ requestId, records: [{ ...row, location }] }),
      ).toThrow();
    },
  );
  it('refuses a missing location and separates v2 null-location digests', () => {
    const { location: _location, ...legacy } = row;
    expect(() =>
      prepareAssetImportV3({ requestId, records: [legacy] }),
    ).toThrow();
    const v2 = prepareAssetImportV2({ requestId, records: [legacy] });
    expect(prepareAssetImportV3(request()).digest).not.toBe(v2.digest);
  });
  it('rejects unexpected request keys and record metadata without mutating input', () => {
    for (const input of [
      null,
      [],
      { ...request(), owner: 'override' },
      { ...request(), records: [{ ...row, id: requestId }] },
      { ...request(), records: [{ ...row, ownerId: 'override' }] },
    ]) {
      expect(() => prepareAssetImportV3(input)).toThrow();
    }
    const input = { requestId, records: [{ ...row, location: ' Room ' }] };
    const before = JSON.stringify(input);
    prepareAssetImportV3(input);
    expect(JSON.stringify(input)).toBe(before);
  });
});
