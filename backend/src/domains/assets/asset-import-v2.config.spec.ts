import { isAssetImportV2Enabled } from './asset-import-v2.config';

describe('v2 explicit capability prerequisites', () => {
  it('stays disabled by default', () => {
    expect(isAssetImportV2Enabled({})).toBe(false);
    expect(isAssetImportV2Enabled({ ASSET_IMPORT_V2_ENABLED: 'false' })).toBe(
      false,
    );
  });
  it.each(['TRUE', '1', '', ' true'])(
    'rejects malformed enablement %s',
    (value) => {
      expect(() =>
        isAssetImportV2Enabled({ ASSET_IMPORT_V2_ENABLED: value }),
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
        isAssetImportV2Enabled({ ...env, ASSET_IMPORT_V2_ENABLED: 'true' }),
      ).toThrow();
    expect(
      isAssetImportV2Enabled({
        ASSET_IMPORT_V2_ENABLED: 'true',
        ASSET_IMPORT_ENABLED: 'true',
        ASSET_DATES_ENABLED: 'true',
      }),
    ).toBe(true);
  });
});
