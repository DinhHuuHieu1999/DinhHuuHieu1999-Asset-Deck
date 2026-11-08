import { isAssetCheckEnabled, validateAssetCheckUpdate } from './asset-check';

describe('manual last checked date contract', () => {
  it.each(['0001-01-01', '2024-02-29', '2026-10-31', null])(
    'accepts explicit historical/today date or clear: %s',
    (lastCheckedOn) => {
      const result = validateAssetCheckUpdate(
        { version: 7, lastCheckedOn },
        '2026-10-31',
      );
      expect(result).toEqual({ version: 7, lastCheckedOn });
      expect(Object.isFrozen(result)).toBe(true);
    },
  );
  it.each([
    null,
    [],
    {},
    { version: 1 },
    { lastCheckedOn: null },
    { version: '1', lastCheckedOn: null },
    { version: 0, lastCheckedOn: null },
    { version: 1.5, lastCheckedOn: null },
    { version: 2147483647, lastCheckedOn: null },
    { version: 1, lastCheckedOn: null, owner: 'other' },
    ...[
      '',
      '2025-02-29',
      '1900-02-29',
      '0000-01-01',
      '2026-11-01',
      '2026-10-31T00:00:00Z',
      ' 2026-10-31',
      '2026-1-1',
      1,
    ].map((lastCheckedOn) => ({ version: 1, lastCheckedOn })),
  ])('rejects malformed, future or implicit updates %#', (input) => {
    expect(() => validateAssetCheckUpdate(input, '2026-10-31')).toThrow(
      'Invalid last checked date',
    );
  });
  it('rejects inherited payloads and invalid server reference', () => {
    expect(() =>
      validateAssetCheckUpdate(
        Object.create({ version: 1, lastCheckedOn: null }),
      ),
    ).toThrow();
    expect(() =>
      validateAssetCheckUpdate(
        { version: 1, lastCheckedOn: null },
        '2026-02-30',
      ),
    ).toThrow('invalid_check_reference_date');
  });
  it('uses the server UTC day, not caller-provided timezone parsing', () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-10-31T23:59:59Z'));
    try {
      expect(
        validateAssetCheckUpdate({ version: 1, lastCheckedOn: '2026-10-31' })
          .lastCheckedOn,
      ).toBe('2026-10-31');
      expect(() =>
        validateAssetCheckUpdate({ version: 1, lastCheckedOn: '2026-11-01' }),
      ).toThrow();
    } finally {
      jest.useRealTimers();
    }
  });
  it('requires explicit valid enablement', () => {
    expect(isAssetCheckEnabled({})).toBe(false);
    expect(isAssetCheckEnabled({ ASSET_CHECK_ENABLED: 'false' })).toBe(false);
    expect(isAssetCheckEnabled({ ASSET_CHECK_ENABLED: 'true' })).toBe(true);
    for (const value of ['', '1', 'TRUE'])
      expect(() =>
        isAssetCheckEnabled({ ASSET_CHECK_ENABLED: value }),
      ).toThrow();
  });
});
