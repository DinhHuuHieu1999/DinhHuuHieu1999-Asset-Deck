import { isAssetImportV3Enabled } from './asset-import-v3.config';

describe('v3 explicit capability prerequisites', () => {
  it('stays disabled by default', () => {
    expect(isAssetImportV3Enabled({})).toBe(false);
    expect(isAssetImportV3Enabled({ ASSET_IMPORT_V3_ENABLED: 'false' })).toBe(
      false,
    );
  });
  it.each(['TRUE', '1', '', ' true'])(
    'rejects malformed enablement %s',
    (value) => {
      expect(() =>
        isAssetImportV3Enabled({ ASSET_IMPORT_V3_ENABLED: value }),
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
        isAssetImportV3Enabled({ ...env, ASSET_IMPORT_V3_ENABLED: 'true' }),
      ).toThrow();
    expect(
      isAssetImportV3Enabled({
        ASSET_IMPORT_V3_ENABLED: 'true',
        ASSET_IMPORT_ENABLED: 'true',
        ASSET_DATES_ENABLED: 'true',
        ASSET_LOCATION_ENABLED: 'true',
      }),
    ).toBe(true);
  });
  it.each([
    'ASSET_IMPORT_ENABLED',
    'ASSET_DATES_ENABLED',
    'ASSET_LOCATION_ENABLED',
  ])('requires %s without requiring export or v2', (missing) => {
    const env = {
      ASSET_IMPORT_V3_ENABLED: 'true',
      ASSET_IMPORT_ENABLED: 'true',
      ASSET_DATES_ENABLED: 'true',
      ASSET_LOCATION_ENABLED: 'true',
      ASSET_IMPORT_V2_ENABLED: 'false',
      ASSET_EXPORT_V3_ENABLED: 'false',
    };
    expect(isAssetImportV3Enabled(env)).toBe(true);
    expect(() =>
      isAssetImportV3Enabled({ ...env, [missing]: 'false' }),
    ).toThrow();
  });
});
