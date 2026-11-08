import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import { prepareAssetImport } from './asset-import';

const requestId = '00000000-0000-4000-8000-000000000001';
const row = {
  name: ' Laptop ',
  category: ' Computer ',
  serial: '%_1 ',
  status: 'stored',
  notes: ' Note ',
};
const request = () => ({ requestId, records: [{ ...row }] });

describe('add-only asset import preparation', () => {
  it('normalizes and freezes editable fields without accepting identities', () => {
    const input = request();
    const value = prepareAssetImport(input);
    expect(value.records[0]).toEqual({
      name: 'Laptop',
      category: 'Computer',
      serial: '%_1',
      status: 'stored',
      notes: 'Note',
    });
    expect(Object.isFrozen(value)).toBe(true);
    expect(Object.isFrozen(value.records)).toBe(true);
    expect(Object.isFrozen(value.records[0])).toBe(true);
    input.records[0].name = 'Changed';
    expect(value.records[0].name).toBe('Laptop');
  });
  it('canonicalizes digest independently of property order and request UUID', () => {
    const first = prepareAssetImport(request());
    const second = prepareAssetImport({
      records: [
        {
          notes: 'Note',
          status: 'stored',
          serial: '%_1',
          category: 'Computer',
          name: 'Laptop',
        },
      ],
      requestId: '00000000-0000-4000-8000-000000000002',
    });
    expect(first.digest).toMatch(/^[0-9a-f]{64}$/u);
    expect(second.digest).toBe(first.digest);
    expect(
      prepareAssetImport({
        ...request(),
        records: [{ ...row, notes: 'Other' }],
      }).digest,
    ).not.toBe(first.digest);
  });
  it('rejects owner, identity, client digest and malformed request shape', () => {
    for (const input of [
      null,
      [],
      {},
      { ...request(), owner: 'someone' },
      { ...request(), digest: '0'.repeat(64) },
      { ...request(), requestId: 'bad' },
      { ...request(), records: [] },
      { ...request(), records: [{ ...row, id: requestId }] },
    ]) {
      expect(() => prepareAssetImport(input)).toThrow(BadRequestException);
    }
  });
  it('rejects blank, NUL, invalid status, oversized fields and malformed Unicode', () => {
    for (const update of [
      { name: ' ' },
      { notes: '\0' },
      { status: 'unknown' },
      { name: 'x'.repeat(121) },
      { notes: '\ud800' },
    ]) {
      expect(() =>
        prepareAssetImport({ ...request(), records: [{ ...row, ...update }] }),
      ).toThrow(BadRequestException);
    }
  });
  it('accepts 500 duplicates as separate records and rejects 501', () => {
    expect(
      prepareAssetImport({
        requestId,
        records: Array.from({ length: 500 }, () => ({ ...row })),
      }).records,
    ).toHaveLength(500);
    expect(() =>
      prepareAssetImport({
        requestId,
        records: Array.from({ length: 501 }, () => ({ ...row })),
      }),
    ).toThrow(PayloadTooLargeException);
  });
  it('rejects oversized UTF-8 bytes even when character limits pass', () => {
    expect(() =>
      prepareAssetImport({
        requestId,
        records: Array.from({ length: 500 }, () => ({
          ...row,
          notes: '\u4e2d'.repeat(2000),
        })),
      }),
    ).toThrow(PayloadTooLargeException);
  });
});
