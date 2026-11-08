import { NotFoundException, UnauthorizedException } from '@nestjs/common';
import { AssetsRepository } from './assets.repository';
import { AssetsService } from './assets.service';
import { AssetsController } from './assets.controller';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';

const owner = '507f1f77bcf86cd799439011';
const id = 'a0000000-0000-4000-8000-000000000001';

describe('owner-scoped asset read', () => {
  it('binds owner and ID rather than scanning inventory pages', async () => {
    const record = { id, name: 'Synthetic' };
    const query = jest.fn().mockResolvedValue({ rows: [record] });
    const repository = new AssetsRepository({
      pool: { query },
    } as unknown as PostgresDatabase);
    expect(await repository.findOne(owner.toUpperCase(), id)).toEqual(record);
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('WHERE owner_id=$1 AND id=$2::uuid'),
      [owner, id],
    );
    await expect(repository.findOne('invalid', id)).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('returns null for absent or foreign rows', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new AssetsRepository({
      pool: { query },
    } as unknown as PostgresDatabase);
    expect(await repository.findOne(owner, id)).toBeNull();
  });
  it('maps unavailable records to the same not-found response', async () => {
    const findOne = jest.fn().mockResolvedValue(null);
    const service = new AssetsService({
      findOne,
    } as unknown as AssetsRepository);
    await expect(service.findOne(owner, id)).rejects.toThrow(NotFoundException);
    const record = { id, name: 'Synthetic' };
    findOne.mockResolvedValue(record);
    expect(await service.findOne(owner, id)).toEqual(record);
  });
  it('requires an authenticated owner and propagates database failures', async () => {
    const findOne = jest
      .fn()
      .mockRejectedValue(new Error('database unavailable'));
    const controller = new AssetsController({
      findOne,
    } as unknown as AssetsService);
    expect(() => controller.findOne({}, id)).toThrow(UnauthorizedException);
    expect(findOne).not.toHaveBeenCalled();
    await expect(
      controller.findOne({ user: { userId: owner } }, id),
    ).rejects.toThrow('database unavailable');
    expect(findOne).toHaveBeenCalledWith(owner, id);
  });
});
