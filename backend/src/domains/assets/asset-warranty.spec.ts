import { BadRequestException } from '@nestjs/common';
import { assetWarrantyWindow } from './asset-warranty';

describe('warranty calendar filter contract', () => {
  it('uses UTC rather than local time for a new filter', () => {
    expect(
      assetWarrantyWindow('expired', '', new Date('2026-10-26T23:30:00-07:00')),
    ).toEqual({ filter: 'expired', asOf: '2026-10-27', through: '2026-11-26' });
  });
  it.each([
    ['2024-02-01', '2024-03-02'],
    ['1900-02-01', '1900-03-03'],
    ['2000-02-01', '2000-03-02'],
    ['2026-12-20', '2027-01-19'],
    ['0001-01-01', '0001-01-31'],
    ['0099-12-20', '0100-01-19'],
    ['9999-12-20', '9999-12-31'],
    ['9999-12-31', '9999-12-31'],
  ])('resolves thirty calendar days after %s', (day, through) => {
    expect(assetWarrantyWindow('expiring_soon', day).through).toBe(through);
  });
  it('keeps an explicit page reference stable across UTC midnight', () => {
    expect(
      assetWarrantyWindow('expired', '2026-10-26', new Date('2026-10-28Z'))
        .asOf,
    ).toBe('2026-10-26');
    expect(Object.isFrozen(assetWarrantyWindow('expired', '2026-10-26'))).toBe(
      true,
    );
  });
  it.each([
    null,
    undefined,
    [],
    {},
    '2026-02-29',
    '0000-01-01',
    '2026-10-26\n',
    '2026-10-26T00:00:00Z',
    '2026-1-01',
    20261026,
  ])('refuses malformed reference %p', (value) => {
    // Undefined selects the documented default parameter, so test it as a filter instead.
    if (value === undefined) {
      expect(() => assetWarrantyWindow(value, '2026-10-26')).toThrow(
        BadRequestException,
      );
    } else {
      expect(() => assetWarrantyWindow('expired', value)).toThrow(
        BadRequestException,
      );
    }
  });
  it.each(['', 'all', 'unknown', 'EXPIRED', ['expired'], null, {}])(
    'refuses unsupported filter %p',
    (value) => {
      expect(() => assetWarrantyWindow(value, '2026-10-26')).toThrow(
        BadRequestException,
      );
    },
  );
});
