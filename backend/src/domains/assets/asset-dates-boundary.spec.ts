jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import {
  BadRequestException,
  ConflictException,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { AssetDatesController } from './asset-dates.controller';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetDatesModule } from './asset-dates.module';
import { isAssetDatesEnabled } from './asset-dates.config';
const owner = '507f1f77bcf86cd799439011';
const id = '72d9a3cd-3eb1-40ea-ac3f-d549d77ff8da';
const input = {
  version: 1,
  purchasedOn: '2026-01-01',
  warrantyExpiresOn: null,
};

describe('date capability boundaries', () => {
  it('defaults off and rejects every ambiguous flag', () => {
    expect(isAssetDatesEnabled({})).toBe(false);
    expect(isAssetDatesEnabled({ ASSET_DATES_ENABLED: 'false' })).toBe(false);
    expect(isAssetDatesEnabled({ ASSET_DATES_ENABLED: 'true' })).toBe(true);
    for (const value of ['', 'TRUE', '1', ' true ', 'yes'])
      expect(() =>
        isAssetDatesEnabled({ ASSET_DATES_ENABLED: value }),
      ).toThrow();
  });
  it('checks explicit date columns at startup and propagates missing schema', async () => {
    const query = jest.fn().mockRejectedValue(new Error('missing schema'));
    const repository = new AssetDatesRepository({ pool: { query } } as never);
    await expect(
      new AssetDatesModule(repository).onModuleInit(),
    ).rejects.toThrow('missing schema');
    expect(query.mock.calls[0][0]).toContain('purchased_on');
    expect(query.mock.calls[0][0]).toContain('warranty_expires_on');
    expect(query.mock.calls[0][0]).toContain('LIMIT 0');
    expect(query.mock.calls[0][0]).not.toMatch(/ALTER|CREATE|UPDATE/);
  });
  it('uses owner and ID predicates without parsing dates into JS timestamps', async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          id,
          version: 1,
          purchasedOn: '0001-01-01',
          warrantyExpiresOn: null,
        },
      ],
    });
    const repository = new AssetDatesRepository({ pool: { query } } as never);
    expect(await repository.read(owner.toUpperCase(), id)).toMatchObject({
      purchasedOn: '0001-01-01',
    });
    expect(query.mock.calls[0][1]).toEqual([owner, id]);
    expect(query.mock.calls[0][0]).toContain('WHERE owner_id=$1 AND id=$2');
    await expect(repository.read('invalid', id)).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('updates only dates and shared version, with null clearing and no silent fallback', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new AssetDatesRepository({ pool: { query } } as never);
    expect(await repository.update(owner, id, input)).toBeNull();
    const [sql, args] = query.mock.calls[0];
    expect(sql).toContain('WHERE owner_id=$1 AND id=$2 AND version=$3');
    expect(sql).toContain('version=version+1');
    expect(sql).not.toMatch(/SET name|SET status|serial=|notes=|category=/);
    expect(args).toEqual([owner, id, 1, '2026-01-01', null]);
  });
  it('hides non-owned/missing reads and stale writes under common errors', async () => {
    const repository = {
      read: jest.fn().mockResolvedValue(null),
      update: jest.fn().mockResolvedValue(null),
    };
    const controller = new AssetDatesController(repository as never);
    await expect(
      controller.read({ user: { userId: owner } }, id, {}),
    ).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      controller.update({ user: { userId: owner } }, id, input, {}),
    ).rejects.toBeInstanceOf(ConflictException);
  });
  it('rejects auth, owner/query injection and omitted date fields before persistence', async () => {
    const repository = { read: jest.fn(), update: jest.fn() };
    const controller = new AssetDatesController(repository as never);
    await expect(controller.read({}, id, {})).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    await expect(
      controller.read({ user: { userId: owner } }, id, { owner: 'another' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      controller.update({ user: { userId: owner } }, id, { version: 1 }, {}),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(repository.read).not.toHaveBeenCalled();
    expect(repository.update).not.toHaveBeenCalled();
  });
});
