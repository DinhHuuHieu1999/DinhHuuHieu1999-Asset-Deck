import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { validate } from 'class-validator';
import { AssetsRepository } from './assets.repository';
import { AssetsService } from './assets.service';
import { AssetsController } from './assets.controller';
import { AssetSerialQueryDto } from './assets.dto';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';

const owner = '507f1f77bcf86cd799439011';
const id = 'a0000000-0000-4000-8000-000000000001';
describe('advisory serial duplicate check', () => {
  it.each([true, false])(
    'returns only the database boolean %s',
    async (duplicate) => {
      const query = jest.fn().mockResolvedValue({ rows: [{ duplicate }] });
      const repository = new AssetsRepository({
        pool: { query },
      } as unknown as PostgresDatabase);
      expect(await repository.serialDuplicate(owner, '%_1', id)).toEqual({
        duplicate,
      });
      const [sql, values] = query.mock.calls[0];
      expect(values).toEqual([owner, '%_1', id]);
      expect(sql).toContain('owner_id=$1 AND serial=$2');
      expect(sql).toContain("serial<>''");
      expect(sql).toContain('id<>$3::uuid');
      expect(sql).not.toMatch(/OFFSET|ILIKE|lower\(serial\)/i);
    },
  );
  it('rejects malformed database responses rather than reporting no match', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new AssetsRepository({
      pool: { query },
    } as unknown as PostgresDatabase);
    await expect(repository.serialDuplicate(owner, '')).rejects.toThrow(
      'asset_serial_check_missing',
    );
    await expect(repository.serialDuplicate('invalid', 'x')).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('normalizes edges without case folding and preserves blank lookup semantics', async () => {
    const serialDuplicate = jest.fn().mockResolvedValue({ duplicate: false });
    const service = new AssetsService({
      serialDuplicate,
    } as unknown as AssetsRepository);
    await service.serialDuplicate(owner, ' AbC%_ ', id);
    expect(serialDuplicate).toHaveBeenLastCalledWith(owner, 'AbC%_', id);
    const unicode = String.fromCodePoint(0x1f527).repeat(120);
    await service.serialDuplicate(owner, unicode);
    expect(serialDuplicate).toHaveBeenLastCalledWith(owner, unicode, undefined);
    await service.serialDuplicate(owner, '  ');
    expect(serialDuplicate).toHaveBeenLastCalledWith(owner, '', undefined);
    expect(() => service.serialDuplicate(owner, 'x'.repeat(121))).toThrow(
      BadRequestException,
    );
    expect(() => service.serialDuplicate(owner, '\0')).toThrow(
      BadRequestException,
    );
  });
  it('requires authenticated owner and does not accept an owner query override', async () => {
    const serialDuplicate = jest.fn().mockResolvedValue({ duplicate: false });
    const controller = new AssetsController({
      serialDuplicate,
    } as unknown as AssetsService);
    expect(() =>
      controller.serialDuplicate({}, new AssetSerialQueryDto()),
    ).toThrow(UnauthorizedException);
    await controller.serialDuplicate(
      { user: { userId: owner } },
      Object.assign(new AssetSerialQueryDto(), { serial: 'x', excludeId: id }),
    );
    expect(serialDuplicate).toHaveBeenCalledWith(owner, 'x', id);
  });
  it('validates query serial and exclusion ID', async () => {
    for (const value of [
      { serial: 'x'.repeat(121) },
      { serial: '\0' },
      { excludeId: 'not-a-uuid' },
    ]) {
      expect(
        (await validate(Object.assign(new AssetSerialQueryDto(), value)))
          .length,
      ).toBeGreaterThan(0);
    }
    expect(
      await validate(
        Object.assign(new AssetSerialQueryDto(), {
          serial: '%_1',
          excludeId: id,
        }),
      ),
    ).toEqual([]);
  });
});
