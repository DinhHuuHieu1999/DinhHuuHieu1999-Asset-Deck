import 'reflect-metadata';
import { validateSync } from 'class-validator';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { assetOrderBy } from './asset-sort';
import { AssetQueryDto } from './assets.dto';
import { AssetWarrantyQueryDto } from './asset-warranty.dto';
import { AssetLocationQueryDto } from './asset-location.controller';
import { AssetsRepository } from './assets.repository';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetLocationRepository } from './asset-location.repository';

const owner = '507f1f77bcf86cd799439011';
describe('inventory sort allowlist and repository contracts', () => {
  it('keeps legacy default and uses deterministic C collation for names', () => {
    expect(assetOrderBy()).toBe('updated_at DESC,id DESC');
    expect(assetOrderBy('name_asc')).toBe('name COLLATE "C" ASC,id ASC');
  });
  it.each(['', 'NAME_ASC', 'name DESC; DROP TABLE assets.assets', null, []])(
    'rejects untrusted SQL sort %p',
    (sort) => {
      expect(() => assetOrderBy(sort)).toThrow('invalid_asset_sort');
    },
  );
  it.each([AssetQueryDto, AssetWarrantyQueryDto, AssetLocationQueryDto])(
    'validates the inherited list query allowlist',
    (Dto) => {
      const dto = new Dto();
      expect(dto.sort).toBe('updated_desc');
      dto.sort = 'name_asc';
      expect(
        validateSync(dto).filter((error) => error.property === 'sort'),
      ).toEqual([]);
      Object.assign(dto, { sort: 'name_asc; DROP' });
      expect(validateSync(dto).some((error) => error.property === 'sort')).toBe(
        true,
      );
    },
  );
  it.each(['regular', 'warranty', 'location'] as const)(
    '%s orders the filtered owner rows before paging and refuses invalid sort',
    async (kind) => {
      const sql = jest.fn().mockResolvedValue({ rows: [] });
      const database = { pool: { query: sql } } as unknown as PostgresDatabase;
      const query = Object.assign(new AssetWarrantyQueryDto(), {
        sort: 'name_asc',
        q: 'literal %_',
        category: 'fixture',
        warranty: 'expired',
        offset: 50,
      });
      const window = {
        filter: 'expired' as const,
        asOf: '2026-10-29',
        through: '2026-11-28',
      };
      const run = () =>
        kind === 'regular'
          ? new AssetsRepository(database).list(owner, query)
          : kind === 'warranty'
            ? new AssetDatesRepository(database).warrantyList(
                owner,
                query,
                window,
              )
            : new AssetLocationRepository(database).list(
                owner,
                query,
                { mode: 'all', location: null },
                window,
              );
      await run();
      expect(sql.mock.calls[0][0]).toContain('WHERE owner_id=$1');
      expect(sql.mock.calls[0][0]).toContain(
        'ORDER BY name COLLATE "C" ASC,id ASC LIMIT 51 OFFSET $2',
      );
      expect(sql.mock.calls[0][1].slice(0, 3)).toEqual([
        owner,
        50,
        'literal %_',
      ]);
      sql.mockClear();
      query.sort = 'updated_desc';
      await run();
      expect(sql.mock.calls[0][0]).toContain(
        'ORDER BY updated_at DESC,id DESC LIMIT 51 OFFSET $2',
      );
      sql.mockClear();
      Object.assign(query, { sort: 'invalid' });
      await expect(run()).rejects.toThrow('invalid_asset_sort');
      expect(sql).not.toHaveBeenCalled();
    },
  );
});
