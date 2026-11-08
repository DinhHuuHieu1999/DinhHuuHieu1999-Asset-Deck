jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import {
  BadRequestException,
  UnauthorizedException,
  UnprocessableEntityException,
  ValidationPipe,
} from '@nestjs/common';
import { buildAssetWarrantyOverview } from './asset-warranty-overview';
import { assetWarrantyWindow } from './asset-warranty';
import { AssetWarrantyOverviewQueryDto } from './asset-warranty.dto';
import { AssetWarrantyController } from './asset-warranty.controller';
import { AssetDatesRepository } from './asset-dates.repository';

const owner = '507f1f77bcf86cd799439011';
const window = assetWarrantyWindow('expired', '2026-10-27');
const counts = {
  total: '7',
  expired: '1',
  expiringSoon: '2',
  later: '3',
  unknown: '1',
};
const pipe = new ValidationPipe({
  transform: true,
  whitelist: true,
  forbidNonWhitelisted: true,
});
function validate(value: unknown): Promise<AssetWarrantyOverviewQueryDto> {
  return pipe.transform(value, {
    type: 'query',
    metatype: AssetWarrantyOverviewQueryDto,
  });
}

describe('complete warranty overview', () => {
  it('returns exactly four disjoint counts and a shared explicit reference', () => {
    expect(buildAssetWarrantyOverview(counts, window)).toEqual({
      complete: true,
      asOf: '2026-10-27',
      through: '2026-11-26',
      total: 7,
      expired: 1,
      expiringSoon: 2,
      later: 3,
      unknown: 1,
    });
  });
  it('accepts empty inventory and safe integer boundary without truncation', () => {
    const zero = {
      total: '0',
      expired: '0',
      expiringSoon: '0',
      later: '0',
      unknown: '0',
    };
    expect(buildAssetWarrantyOverview(zero, window).total).toBe(0);
    expect(
      buildAssetWarrantyOverview(
        { ...zero, total: '9007199254740991', unknown: '9007199254740991' },
        window,
      ).unknown,
    ).toBe(Number.MAX_SAFE_INTEGER);
  });
  it.each(['', '-1', '01', '1.5', 'NaN', ' 1', '1e2', null, 1, undefined])(
    'refuses malformed aggregate count %p',
    (value) => {
      expect(() =>
        buildAssetWarrantyOverview(
          { ...counts, expired: value } as never,
          window,
        ),
      ).toThrow('asset_warranty_overview_invalid_aggregate');
    },
  );
  it('rejects inconsistent totals and unsafe counts/sums instead of partial success', () => {
    expect(() =>
      buildAssetWarrantyOverview({ ...counts, total: '8' }, window),
    ).toThrow('asset_warranty_overview_inconsistent_aggregate');
    expect(() =>
      buildAssetWarrantyOverview(
        { ...counts, total: '9007199254740992' },
        window,
      ),
    ).toThrow(UnprocessableEntityException);
    expect(() =>
      buildAssetWarrantyOverview(
        { ...counts, expired: '9007199254740991', later: '1' },
        window,
      ),
    ).toThrow(UnprocessableEntityException);
  });
  it('validates only an optional reference; no list filters or owner input', async () => {
    expect(await validate({})).toEqual({ asOf: '' });
    expect(await validate({ asOf: '0001-01-01' })).toEqual({
      asOf: '0001-01-01',
    });
  });
  it.each([
    { ownerId: owner },
    { warranty: 'expired' },
    { q: '' },
    { status: 'stored' },
    { category: 'fixture' },
    { offset: '0' },
    { asOf: null },
    { asOf: [] },
    { asOf: '2026-10-27Z' },
  ])('rejects unsupported query %p', async (query) => {
    await expect(validate(query)).rejects.toBeInstanceOf(BadRequestException);
  });
  it('authenticates before repository access and rejects impossible dates', async () => {
    const repository = {
      warrantyOverview: jest.fn().mockResolvedValue({ total: 7 }),
    };
    const controller = new AssetWarrantyController(repository as never);
    const query = await validate({ asOf: window.asOf });
    await expect(
      controller.overview({ user: { userId: owner } }, query),
    ).resolves.toEqual({ total: 7 });
    expect(repository.warrantyOverview).toHaveBeenCalledWith(owner, window);
    for (const request of [{}, { user: { userId: 'invalid' } }]) {
      expect(() => controller.overview(request, query)).toThrow(
        UnauthorizedException,
      );
    }
    expect(() =>
      controller.overview({ user: { userId: owner } }, { asOf: '2026-02-29' }),
    ).toThrow(BadRequestException);
    expect(repository.warrantyOverview).toHaveBeenCalledTimes(1);
    expect(
      Reflect.getMetadata('path', AssetWarrantyController.prototype.overview),
    ).toBe('overview');
    expect(
      Reflect.getMetadata(
        '__headers__',
        AssetWarrantyController.prototype.overview,
      ),
    ).toContainEqual({ name: 'Cache-Control', value: 'no-store' });
  });
  it('uses UTC today when reference is omitted and caps the calendar horizon', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-10-27T23:59:59Z'));
    try {
      const repository = { warrantyOverview: jest.fn().mockResolvedValue({}) };
      const controller = new AssetWarrantyController(repository as never);
      await controller.overview(
        { user: { userId: owner } },
        await validate({}),
      );
      expect(repository.warrantyOverview).toHaveBeenLastCalledWith(
        owner,
        window,
      );
      await controller.overview(
        { user: { userId: owner } },
        { asOf: '9999-12-31' },
      );
      expect(repository.warrantyOverview).toHaveBeenLastCalledWith(
        owner,
        expect.objectContaining({ asOf: '9999-12-31', through: '9999-12-31' }),
      );
    } finally {
      jest.useRealTimers();
    }
  });
  it('aggregates the entire owner in one statement without grouping, paging or private fields', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [counts] });
    const repository = new AssetDatesRepository({ pool: { query } } as never);
    expect(
      await repository.warrantyOverview(owner.toUpperCase(), window),
    ).toMatchObject({ total: 7, complete: true });
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, parameters] = query.mock.calls[0];
    expect(parameters).toEqual([owner, window.asOf, window.through]);
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('warranty_expires_on < $2::date');
    expect(sql).toContain('warranty_expires_on >= $2::date');
    expect(sql).toContain('warranty_expires_on <= $3::date');
    expect(sql).toContain('warranty_expires_on > $3::date');
    expect(sql).toContain('warranty_expires_on IS NULL');
    expect(sql).not.toMatch(
      /LIMIT|OFFSET|GROUP BY|CURRENT_DATE|serial|notes|UPDATE|INSERT|DELETE/,
    );
    await expect(
      repository.warrantyOverview('invalid', window),
    ).rejects.toThrow('invalid_asset_owner');
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('refuses missing/duplicate aggregate rows and propagates database failure', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new AssetDatesRepository({ pool: { query } } as never);
    await expect(repository.warrantyOverview(owner, window)).rejects.toThrow(
      'asset_warranty_overview_missing_aggregate',
    );
    query.mockResolvedValueOnce({ rows: [counts, counts] });
    await expect(repository.warrantyOverview(owner, window)).rejects.toThrow(
      'asset_warranty_overview_missing_aggregate',
    );
    query.mockRejectedValueOnce(new Error('synthetic unavailable'));
    await expect(repository.warrantyOverview(owner, window)).rejects.toThrow(
      'synthetic unavailable',
    );
  });
});
