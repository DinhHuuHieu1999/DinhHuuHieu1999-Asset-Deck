import {
  UnauthorizedException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { buildAssetOverview } from './asset-overview';
import { AssetsRepository } from './assets.repository';
import { AssetsService } from './assets.service';
import { AssetsController } from './assets.controller';

const owner = '507f1f77bcf86cd799439011';
describe('inventory overview', () => {
  it('accepts 64 Unicode code points, matching the database category limit', () => {
    const category = String.fromCodePoint(0x1f527).repeat(64);
    expect(
      buildAssetOverview([{ category, status: 'stored', count: '1' }])
        .byCategory,
    ).toEqual([{ category, count: 1 }]);
    expect(() =>
      buildAssetOverview([
        { category: category + 'x', status: 'stored', count: '1' },
      ]),
    ).toThrow();
  });
  it('returns complete zero counts for an empty account', () => {
    expect(buildAssetOverview([])).toEqual({
      complete: true,
      total: 0,
      byStatus: { in_use: 0, stored: 0, repair: 0, retired: 0 },
      byCategory: [],
    });
  });
  it('aggregates all status groups and preserves literal case-sensitive categories', () => {
    const result = buildAssetOverview([
      { category: 'network', status: 'stored', count: '51' },
      { category: 'network', status: 'repair', count: '2' },
      { category: 'Network', status: 'in_use', count: '1' },
      { category: '%_機器', status: 'retired', count: '3' },
    ]);
    expect(result.total).toBe(57);
    expect(result.byStatus).toEqual({
      in_use: 1,
      stored: 51,
      repair: 2,
      retired: 3,
    });
    expect(result.byCategory).toEqual([
      { category: '%_機器', count: 3 },
      { category: 'Network', count: 1 },
      { category: 'network', count: 53 },
    ]);
  });
  it.each(['0', '-1', '1.5', '01', 'NaN', '9007199254740992'])(
    'rejects invalid count %s',
    (count) => {
      expect(() =>
        buildAssetOverview([{ category: 'a', status: 'stored', count }]),
      ).toThrow();
    },
  );
  it('rejects invalid status and duplicate groups', () => {
    expect(() =>
      buildAssetOverview([{ category: 'a', status: 'active', count: '1' }]),
    ).toThrow();
    const row = { category: 'a', status: 'stored', count: '1' };
    expect(() => buildAssetOverview([row, row])).toThrow();
  });
  it('rejects sum overflow even when each count is safe', () => {
    expect(() =>
      buildAssetOverview([
        { category: 'a', status: 'stored', count: '9007199254740991' },
        { category: 'a', status: 'repair', count: '1' },
      ]),
    ).toThrow('asset_overview_count_overflow');
  });
  it('allows 200 categories and refuses 201 without a partial result', () => {
    const rows = Array.from({ length: 201 }, (_, i) => ({
      category: `category-${i}`,
      status: 'stored',
      count: '1',
    }));
    expect(buildAssetOverview(rows.slice(0, 200)).total).toBe(200);
    expect(() => buildAssetOverview(rows)).toThrow(
      UnprocessableEntityException,
    );
  });
  it('uses one owner-bound aggregate statement without pagination or list filters', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new AssetsRepository({ pool: { query } } as never);
    expect(await repository.overview(owner.toUpperCase())).toMatchObject({
      total: 0,
    });
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, params] = query.mock.calls[0];
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('GROUP BY category, status');
    expect(sql).not.toContain('OFFSET');
    expect(params).toEqual([owner, 801]);
    await expect(repository.overview('invalid')).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('extracts owner from authentication and refuses missing/invalid accounts', async () => {
    const overview = jest.fn().mockResolvedValue({ total: 7 });
    const controller = new AssetsController(
      new AssetsService({ overview } as never),
    );
    expect(await controller.overview({ user: { userId: owner } })).toEqual({
      total: 7,
    });
    expect(overview).toHaveBeenCalledWith(owner);
    expect(() => controller.overview({})).toThrow(UnauthorizedException);
    expect(() => controller.overview({ user: { userId: 'invalid' } })).toThrow(
      UnauthorizedException,
    );
    expect(overview).toHaveBeenCalledTimes(1);
  });
});
