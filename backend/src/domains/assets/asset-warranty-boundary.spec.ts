jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import {
  BadRequestException,
  UnauthorizedException,
  UnprocessableEntityException,
  ValidationPipe,
} from '@nestjs/common';
import { AssetWarrantyQueryDto } from './asset-warranty.dto';
import { AssetWarrantyController } from './asset-warranty.controller';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetDatesModule } from './asset-dates.module';
import { assetWarrantyWindow } from './asset-warranty';

const owner = '507f1f77bcf86cd799439011';
const pipe = new ValidationPipe({
  transform: true,
  whitelist: true,
  forbidNonWhitelisted: true,
});
function validate(value: unknown): Promise<AssetWarrantyQueryDto> {
  return pipe.transform(value, {
    type: 'query',
    metatype: AssetWarrantyQueryDto,
  });
}
const window = assetWarrantyWindow('expired', '2026-10-26');

describe('warranty list boundary', () => {
  it('validates bounded inherited search/status/category and paging defaults', async () => {
    expect(await validate({ warranty: 'expired' })).toEqual({
      sort: 'updated_desc',
      q: '',
      status: '',
      category: '',
      offset: 0,
      warranty: 'expired',
      asOf: '',
    });
    expect(
      await validate({
        warranty: 'expiring_soon',
        q: '%_',
        category: ' Laptop ',
        status: 'repair',
        offset: '50',
        asOf: '2026-10-26',
      }),
    ).toMatchObject({ offset: 50 });
  });
  it.each([
    {},
    { warranty: 'all' },
    { warranty: ['expired'] },
    { ownerId: owner },
    { q: 'x'.repeat(121) },
    { category: 'x'.repeat(65) },
    { q: 'bad\0text' },
    { status: 'active' },
    { offset: '-1' },
    { offset: '100001' },
    { offset: '0.5' },
    { asOf: null },
    { asOf: [] },
    { asOf: '2026-10-26Z' },
  ])('refuses invalid or unknown query before use: %p', async (invalid) => {
    await expect(
      validate({
        warranty: 'expired',
        ...invalid,
        ...(!Object.keys(invalid).length ? { warranty: undefined } : {}),
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
  it('uses authenticated owner only and returns explicit calendar reference', async () => {
    const repository = {
      warrantyList: jest.fn().mockResolvedValue({ items: [], ...window }),
    };
    const controller = new AssetWarrantyController(repository as never);
    const query = await validate({ warranty: 'expired', asOf: '2026-10-26' });
    await expect(
      controller.list({ user: { userId: owner } }, query),
    ).resolves.toMatchObject({ items: [], asOf: '2026-10-26' });
    expect(repository.warrantyList).toHaveBeenCalledWith(owner, query, window);
    for (const request of [{}, { user: { userId: 'invalid' } }]) {
      expect(() => controller.list(request, query)).toThrow(
        UnauthorizedException,
      );
    }
    const badDay = await validate({ warranty: 'expired', asOf: '2026-02-29' });
    expect(() => controller.list({ user: { userId: owner } }, badDay)).toThrow(
      BadRequestException,
    );
    expect(repository.warrantyList).toHaveBeenCalledTimes(1);
  });
  it('registers only in the existing migration-gated dates module', () => {
    expect(Reflect.getMetadata('controllers', AssetDatesModule)).toContain(
      AssetWarrantyController,
    );
    expect(Reflect.getMetadata('path', AssetWarrantyController)).toBe(
      'assets/warranty',
    );
    expect(
      Reflect.getMetadata(
        '__headers__',
        AssetWarrantyController.prototype.list,
      ),
    ).toContainEqual({ name: 'Cache-Control', value: 'no-store' });
  });
  it('binds literal predicates and dates, applies owner and filters before paging', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repo = new AssetDatesRepository({ pool: { query } } as never);
    const params = await validate({
      warranty: 'expired',
      asOf: '2026-10-26',
      offset: '50',
      q: " %_' OR 1=1 -- ",
      category: ' Laptop ',
      status: 'stored',
    });
    expect(
      await repo.warrantyList(owner.toUpperCase(), params, window),
    ).toEqual({
      items: [],
      nextOffset: null,
      warranty: 'expired',
      asOf: '2026-10-26',
      through: '2026-11-25',
    });
    const [sql, args] = query.mock.calls[0];
    expect(args).toEqual([
      owner,
      50,
      "%_' OR 1=1 --",
      'stored',
      'Laptop',
      'expired',
      '2026-10-26',
      '2026-11-25',
    ]);
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('strpos(lower(name),lower($3))');
    expect(sql).toContain('warranty_expires_on < $7::date');
    expect(sql).toContain('warranty_expires_on >= $7::date');
    expect(sql).toContain('warranty_expires_on <= $8::date');
    expect(sql.indexOf('warranty_expires_on <=')).toBeLessThan(
      sql.indexOf('LIMIT 51 OFFSET $2'),
    );
    expect(sql).not.toContain('OR 1=1');
    expect(sql).not.toMatch(/SELECT \*|UPDATE|INSERT|DELETE|CURRENT_DATE/);
    await expect(repo.warrantyList('invalid', params, window)).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).toHaveBeenCalledTimes(1);
  });
  it.each([0, 1, 50, 51])(
    'bounds a %i-row result without hidden continuation',
    async (count) => {
      const rows = Array.from({ length: count }, (_, i) => ({ id: String(i) }));
      const query = jest.fn().mockResolvedValue({ rows });
      const repo = new AssetDatesRepository({ pool: { query } } as never);
      const params = await validate({ warranty: 'expired', offset: '50' });
      const result = await repo.warrantyList(owner, params, window);
      expect(result.items).toEqual(rows.slice(0, 50));
      expect(result.nextOffset).toBe(count > 50 ? 100 : null);
    },
  );
  it('fails explicitly at traversal limit and propagates database errors', async () => {
    const query = jest.fn().mockResolvedValue({ rows: Array(51).fill({}) });
    const repo = new AssetDatesRepository({ pool: { query } } as never);
    const params = await validate({ warranty: 'expired', offset: '100000' });
    await expect(
      repo.warrantyList(owner, params, window),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    query.mockRejectedValueOnce(new Error('synthetic database unavailable'));
    await expect(repo.warrantyList(owner, params, window)).rejects.toThrow(
      'synthetic database unavailable',
    );
  });
});
