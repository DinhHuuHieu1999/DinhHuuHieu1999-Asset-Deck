import { isAssetImportV4Enabled } from './asset-import-v4.config';

describe('v4 explicit capability prerequisites', () => {
  it('stays disabled by default', () => {
    expect(isAssetImportV4Enabled({})).toBe(false);
    expect(isAssetImportV4Enabled({ ASSET_IMPORT_V4_ENABLED: 'false' })).toBe(
      false,
    );
  });
  it.each(['TRUE', '1', '', ' true'])(
    'rejects malformed enablement %s',
    (value) => {
      expect(() =>
        isAssetImportV4Enabled({ ASSET_IMPORT_V4_ENABLED: value }),
      ).toThrow();
    },
  );
  it('requires both legacy import and dates flags', () => {
    for (const env of [
      {},
      { ASSET_IMPORT_ENABLED: 'true' },
      { ASSET_DATES_ENABLED: 'true' },
    ])
      expect(() =>
        isAssetImportV4Enabled({ ...env, ASSET_IMPORT_V4_ENABLED: 'true' }),
      ).toThrow();
    expect(
      isAssetImportV4Enabled({
        ASSET_IMPORT_V4_ENABLED: 'true',
        ASSET_IMPORT_ENABLED: 'true',
        ASSET_DATES_ENABLED: 'true',
        ASSET_LOCATION_ENABLED: 'true',
        ASSET_CHECK_ENABLED: 'true',
      }),
    ).toBe(true);
  });
  it.each([
    'ASSET_IMPORT_ENABLED',
    'ASSET_DATES_ENABLED',
    'ASSET_LOCATION_ENABLED',
    'ASSET_CHECK_ENABLED',
  ])('requires %s without requiring export or v2', (missing) => {
    const env = {
      ASSET_IMPORT_V4_ENABLED: 'true',
      ASSET_IMPORT_ENABLED: 'true',
      ASSET_DATES_ENABLED: 'true',
      ASSET_LOCATION_ENABLED: 'true',
      ASSET_CHECK_ENABLED: 'true',
      ASSET_IMPORT_V2_ENABLED: 'false',
      ASSET_EXPORT_V3_ENABLED: 'false',
    };
    expect(isAssetImportV4Enabled(env)).toBe(true);
    expect(() =>
      isAssetImportV4Enabled({ ...env, [missing]: 'false' }),
    ).toThrow();
  });
});
