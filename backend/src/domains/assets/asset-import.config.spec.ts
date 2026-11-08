import { isAssetImportEnabled } from './asset-import.config';

describe('explicit import opt-in', () => {
  it('defaults off and enables only exact true', () => {
    expect(isAssetImportEnabled({})).toBe(false);
    expect(isAssetImportEnabled({ ASSET_IMPORT_ENABLED: 'false' })).toBe(false);
    expect(isAssetImportEnabled({ ASSET_IMPORT_ENABLED: 'true' })).toBe(true);
  });
  it.each(['', 'yes', '1', 'TRUE', ' true '])(
    'rejects ambiguous flag %j',
    (value) => {
      expect(() =>
        isAssetImportEnabled({ ASSET_IMPORT_ENABLED: value }),
      ).toThrow();
    },
  );
});
