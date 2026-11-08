jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import { AssetImportV2Module } from './asset-import-v2.module';
import { AssetImportV2Repository } from './asset-import-v2.repository';

describe('import readiness gate', () => {
  it('awaits read-only schema readiness', async () => {
    const repository = { assertReady: jest.fn().mockResolvedValue(undefined) };
    await new AssetImportV2Module(
      repository as unknown as AssetImportV2Repository,
    ).onModuleInit();
    expect(repository.assertReady).toHaveBeenCalledTimes(1);
  });
  it('propagates missing schema failure without retry or migration', async () => {
    const failure = new Error('synthetic schema unavailable');
    const repository = { assertReady: jest.fn().mockRejectedValue(failure) };
    await expect(
      new AssetImportV2Module(
        repository as unknown as AssetImportV2Repository,
      ).onModuleInit(),
    ).rejects.toBe(failure);
    expect(repository.assertReady).toHaveBeenCalledTimes(1);
  });
});
