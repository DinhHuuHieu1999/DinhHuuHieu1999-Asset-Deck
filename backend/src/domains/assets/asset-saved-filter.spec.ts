import {
  assertSavedFilterCapabilities,
  validateSavedFilterName,
  validateSavedFilterQuery,
} from './asset-saved-filter';

const base = {
  q: '',
  status: '',
  category: '',
  sort: 'updated_desc',
  locationMode: 'all',
  location: '',
  warranty: 'all',
  asOf: '',
  checkMode: 'all',
  checkBefore: '',
  checkOnOrAfter: '',
};

describe('saved filter schema v1', () => {
  it('returns an immutable detached query with literal search characters', () => {
    const input = { ...base, q: '%_Test' };
    const result = validateSavedFilterQuery(input);
    input.q = 'changed';
    expect(result.q).toBe('%_Test');
    expect(Object.isFrozen(result)).toBe(true);
  });
  it.each(['owner', 'offset', 'token', 'schemaVersion'])(
    'rejects extra field %s',
    (key) => {
      expect(() => validateSavedFilterQuery({ ...base, [key]: 'x' })).toThrow();
    },
  );
  it.each([null, [], {}, { ...base, q: undefined }, { ...base, sort: 'sql' }])(
    'rejects malformed shape',
    (value) => {
      expect(() => validateSavedFilterQuery(value)).toThrow();
    },
  );
  it('keeps fixed leap dates and rejects rollover dates', () => {
    expect(
      validateSavedFilterQuery({
        ...base,
        warranty: 'expired',
        asOf: '2024-02-29',
      }).asOf,
    ).toBe('2024-02-29');
    expect(() =>
      validateSavedFilterQuery({
        ...base,
        warranty: 'expired',
        asOf: '2023-02-29',
      }),
    ).toThrow();
  });
  it('requires exact location and refuses stale dependent text', () => {
    expect(
      validateSavedFilterQuery({
        ...base,
        locationMode: 'exact',
        location: 'Room %_1',
      }).location,
    ).toBe('Room %_1');
    expect(() =>
      validateSavedFilterQuery({ ...base, locationMode: 'exact' }),
    ).toThrow();
    expect(() =>
      validateSavedFilterQuery({ ...base, location: 'stale' }),
    ).toThrow();
  });
  it('rejects contradictory check dates', () => {
    expect(() =>
      validateSavedFilterQuery({ ...base, checkBefore: '2024-03-01' }),
    ).toThrow();
    expect(
      validateSavedFilterQuery({
        ...base,
        checkMode: 'on_or_after',
        checkOnOrAfter: '2024-03-01',
      }).checkOnOrAfter,
    ).toBe('2024-03-01');
  });
  it.each([
    { ...base, locationMode: 'unknown' },
    { ...base, warranty: 'expired', asOf: '2024-03-01' },
    { ...base, checkMode: 'unchecked' },
    { ...base, sort: 'checked_asc' },
  ])(
    'refuses unavailable capabilities without changing stored data',
    (input) => {
      const query = validateSavedFilterQuery(input);
      expect(() =>
        assertSavedFilterCapabilities(query, {
          location: false,
          warranty: false,
          check: false,
        }),
      ).toThrow('unavailable');
      expect(() =>
        assertSavedFilterCapabilities(query, {
          location: true,
          warranty: true,
          check: true,
        }),
      ).not.toThrow();
    },
  );
  it('normalizes bounded labels and rejects unsafe labels', () => {
    expect(validateSavedFilterName('  Repairs  ')).toBe('Repairs');
    for (const value of ['', ' ', 'x'.repeat(61), 'bad\nname', null]) {
      expect(() => validateSavedFilterName(value)).toThrow();
    }
  });
});
