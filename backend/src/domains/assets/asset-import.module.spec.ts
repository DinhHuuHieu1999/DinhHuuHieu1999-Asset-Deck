jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import { AssetImportModule } from './asset-import.module';
import { AssetImportRepository } from './asset-import.repository';

describe('import readiness gate', () => {
  it('awaits read-only schema readiness', async () => {
    const repository = { assertReady: jest.fn().mockResolvedValue(undefined) };
    await new AssetImportModule(
      repository as unknown as AssetImportRepository,
    ).onModuleInit();
    expect(repository.assertReady).toHaveBeenCalledTimes(1);
  });
  it('propagates missing schema failure without retry or migration', async () => {
    const failure = new Error('synthetic schema unavailable');
    const repository = { assertReady: jest.fn().mockRejectedValue(failure) };
    await expect(
      new AssetImportModule(
        repository as unknown as AssetImportRepository,
      ).onModuleInit(),
    ).rejects.toBe(failure);
    expect(repository.assertReady).toHaveBeenCalledTimes(1);
  });
});
