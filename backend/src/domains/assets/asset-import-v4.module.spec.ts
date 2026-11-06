jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import { AssetImportV4Module } from './asset-import-v4.module';
import { AssetImportV4Repository } from './asset-import-v4.repository';

describe('import readiness gate', () => {
  it('awaits read-only schema readiness', async () => {
    const repository = { assertReady: jest.fn().mockResolvedValue(undefined) };
    await new AssetImportV4Module(
      repository as unknown as AssetImportV4Repository,
    ).onModuleInit();
    expect(repository.assertReady).toHaveBeenCalledTimes(1);
  });
  it('propagates missing schema failure without retry or migration', async () => {
    const failure = new Error('synthetic schema unavailable');
    const repository = { assertReady: jest.fn().mockRejectedValue(failure) };
    await expect(
      new AssetImportV4Module(
        repository as unknown as AssetImportV4Repository,
      ).onModuleInit(),
    ).rejects.toBe(failure);
    expect(repository.assertReady).toHaveBeenCalledTimes(1);
  });
});
