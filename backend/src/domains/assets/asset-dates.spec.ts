import { BadRequestException } from '@nestjs/common';
import { isAssetCalendarDate, validateAssetDatesUpdate } from './asset-dates';

const input = {
  version: 1,
  purchasedOn: '2026-10-26',
  warrantyExpiresOn: '2028-10-26',
};
describe('purchase/warranty calendar contract', () => {
  it.each([
    '0001-01-01',
    '9999-12-31',
    '2000-02-29',
    '2024-02-29',
    '2026-04-30',
  ])('accepts real Gregorian day %s', (date) => {
    expect(isAssetCalendarDate(date)).toBe(true);
  });
  it.each([
    null,
    '',
    20261026,
    '0000-01-01',
    '1900-02-29',
    '2026-02-29',
    '2026-04-31',
    '2026-00-01',
    '2026-13-01',
    '2026-01-00',
    '2026-1-01',
    ' 2026-01-01',
    '2026-01-01 ',
    '2026-01-01T00:00:00Z',
    '2026-01-01+07:00',
    '2026-01-01\n',
  ])('rejects invalid day %j', (date) => {
    expect(isAssetCalendarDate(date)).toBe(false);
  });
  it('accepts explicit unknown dates, one known date, equality and future dates', () => {
    for (const dates of [
      { purchasedOn: null, warrantyExpiresOn: null },
      { purchasedOn: '2026-01-01', warrantyExpiresOn: null },
      { purchasedOn: null, warrantyExpiresOn: '2026-01-01' },
      { purchasedOn: '9999-12-31', warrantyExpiresOn: '9999-12-31' },
    ])
      expect(validateAssetDatesUpdate({ version: 1, ...dates })).toEqual({
        version: 1,
        ...dates,
      });
  });
  it.each([
    {},
    [],
    null,
    { ...input, version: '1' },
    { ...input, version: 0 },
    { ...input, version: 1.5 },
    { ...input, version: 2147483647 },
    { ...input, purchasedOn: undefined },
    { ...input, owner: 'another' },
    { version: 1, purchasedOn: null },
    { ...input, purchasedOn: '2028-10-27' },
    { ...input, warrantyExpiresOn: 'invalid' },
  ])('rejects unsafe replacement %j', (value) => {
    expect(() => validateAssetDatesUpdate(value)).toThrow(BadRequestException);
  });
  it('returns an immutable copy without altering the submitted draft', () => {
    const result = validateAssetDatesUpdate(input);
    expect(result).not.toBe(input);
    expect(Object.isFrozen(result)).toBe(true);
    expect(input.purchasedOn).toBe('2026-10-26');
  });
});
