jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import { isAssetSavedFilterEnabled } from './asset-saved-filter.config';
import { AssetSavedFilterModule } from './asset-saved-filter.module';
import type { AssetSavedFilterRepository } from './asset-saved-filter.repository';
describe('saved filter opt-in readiness', () => {
  it('defaults off and accepts only exact boolean strings', () => {
    expect(isAssetSavedFilterEnabled({})).toBe(false);
    expect(
      isAssetSavedFilterEnabled({ ASSET_SAVED_FILTERS_ENABLED: 'false' }),
    ).toBe(false);
    expect(
      isAssetSavedFilterEnabled({ ASSET_SAVED_FILTERS_ENABLED: 'true' }),
    ).toBe(true);
    for (const value of ['', '1', 'TRUE'])
      expect(() =>
        isAssetSavedFilterEnabled({ ASSET_SAVED_FILTERS_ENABLED: value }),
      ).toThrow();
  });
  it('propagates missing schema instead of starting partially ready', async () => {
    const ready = jest.fn().mockRejectedValue(new Error('missing schema'));
    const module = new AssetSavedFilterModule({
      ready,
    } as unknown as AssetSavedFilterRepository);
    await expect(module.onModuleInit()).rejects.toThrow('missing schema');
    expect(ready).toHaveBeenCalledTimes(1);
  });
});
