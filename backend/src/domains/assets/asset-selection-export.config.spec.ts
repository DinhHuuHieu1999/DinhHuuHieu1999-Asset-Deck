jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import { isAssetSelectionExportEnabled } from './asset-selection-export.config';
import { AssetSelectionExportModule } from './asset-selection-export.module';
describe('selection export opt-in', () => {
  it('defaults off and rejects malformed flags or missing prerequisites', () => {
    expect(isAssetSelectionExportEnabled({})).toBe(false);
    expect(
      isAssetSelectionExportEnabled({
        ASSET_SELECTION_EXPORT_ENABLED: 'false',
      }),
    ).toBe(false);
    for (const value of ['TRUE', '1', ''])
      expect(() =>
        isAssetSelectionExportEnabled({
          ASSET_SELECTION_EXPORT_ENABLED: value,
        }),
      ).toThrow();
    expect(() =>
      isAssetSelectionExportEnabled({ ASSET_SELECTION_EXPORT_ENABLED: 'true' }),
    ).toThrow();
    expect(
      isAssetSelectionExportEnabled({
        ASSET_SELECTION_EXPORT_ENABLED: 'true',
        ASSET_DATES_ENABLED: 'true',
        ASSET_LOCATION_ENABLED: 'true',
      }),
    ).toBe(true);
  });
  it('propagates readiness failure without retry or migration', async () => {
    const failure = new Error('missing synthetic schema');
    const ready = jest.fn().mockRejectedValue(failure);
    await expect(
      new AssetSelectionExportModule({ ready } as never).onModuleInit(),
    ).rejects.toBe(failure);
    expect(ready).toHaveBeenCalledTimes(1);
  });
});
