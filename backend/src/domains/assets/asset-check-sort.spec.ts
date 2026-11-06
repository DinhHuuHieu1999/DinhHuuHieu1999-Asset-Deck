import 'reflect-metadata';
import { validateSync } from 'class-validator';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { assetListOrderBy, assetOrderBy, ASSET_SORTS } from './asset-sort';
import { AssetQueryDto } from './assets.dto';
import { AssetWarrantyQueryDto } from './asset-warranty.dto';
import { AssetLocationQueryDto } from './asset-location.controller';
import { AssetsRepository } from './assets.repository';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetLocationRepository } from './asset-location.repository';
import { assetSelectionQuery } from './asset-selection-export.controller';
import { assetSelectionV2Query } from './asset-selection-export-v2.controller';

const owner = '507f1f77bcf86cd799439011';

describe('oldest check-date list ordering without widening export contracts', () => {
  const original = process.env.ASSET_CHECK_ENABLED;
  beforeEach(() => {
    delete process.env.ASSET_CHECK_ENABLED;
  });
  afterEach(() => {
    if (original === undefined) delete process.env.ASSET_CHECK_ENABLED;
    else process.env.ASSET_CHECK_ENABLED = original;
  });

  it('preserves both legacy fixed fragments and the serialized allowlist', () => {
    expect(ASSET_SORTS).toEqual(['updated_desc', 'name_asc']);
    expect(assetListOrderBy()).toBe(assetOrderBy());
    expect(assetListOrderBy('name_asc')).toBe(assetOrderBy('name_asc'));
    expect(() => assetOrderBy('checked_asc')).toThrow('invalid_asset_sort');
  });

  it('requires check capability and orders known dates, NULL last, stable UUID ties', () => {
    expect(() => assetListOrderBy('checked_asc')).toThrow('unavailable');
    process.env.ASSET_CHECK_ENABLED = 'true';
    expect(assetListOrderBy('checked_asc')).toBe(
      'last_checked_on ASC NULLS LAST,id ASC',
    );
    for (const sort of [
      'checked_desc',
      'checked_asc; DROP',
      ['checked_asc'],
      null,
    ])
      expect(() => assetListOrderBy(sort)).toThrow('invalid_asset_sort');
  });

  it.each([AssetQueryDto, AssetWarrantyQueryDto, AssetLocationQueryDto])(
    'accepts the list-only value in inherited DTOs',
    (Dto) => {
      const dto = Object.assign(new Dto(), { sort: 'checked_asc' });
      expect(
        validateSync(dto).filter((error) => error.property === 'sort'),
      ).toEqual([]);
    },
  );

  it.each(['base', 'warranty', 'location', 'combined'] as const)(
    '%s orders the owner-filtered query before pagination and fails closed when off',
    async (kind) => {
      const sql = jest.fn().mockResolvedValue({ rows: [] });
      const database = { pool: { query: sql } } as unknown as PostgresDatabase;
      const input = Object.assign(new AssetWarrantyQueryDto(), {
        sort: 'checked_asc',
        q: 'literal %_',
        status: 'stored',
        category: 'fixture',
        offset: 50,
      });
      const window = {
        filter: 'expired' as const,
        asOf: '2026-11-06',
        through: '2026-12-06',
      };
      const run = () =>
        kind === 'base'
          ? new AssetsRepository(database).list(owner, input)
          : kind === 'warranty'
            ? new AssetDatesRepository(database).warrantyList(
                owner,
                input,
                window,
              )
            : new AssetLocationRepository(database).list(
                owner,
                input,
                { mode: 'exact', location: 'room %_' },
                kind === 'combined' ? window : undefined,
              );
      await expect(run()).rejects.toThrow('unavailable');
      expect(sql).not.toHaveBeenCalled();
      process.env.ASSET_CHECK_ENABLED = 'true';
      for (const mode of [
        'all',
        'unchecked',
        'before',
        'on_or_after',
      ] as const) {
        input.checkMode = mode;
        input.checkBefore = mode === 'before' ? '2024-03-01' : '';
        input.checkOnOrAfter = mode === 'on_or_after' ? '2024-03-01' : '';
        await run();
        const [statement, values] = sql.mock.calls.at(-1)!;
        expect(statement).toContain('WHERE owner_id=$1');
        expect(statement).toContain(
          'ORDER BY last_checked_on ASC NULLS LAST,id ASC LIMIT 51 OFFSET $2',
        );
        expect(values.slice(0, 3)).toEqual([owner, 50, 'literal %_']);
      }
    },
  );

  it('rejects new sort in both legacy selection routes, even with check capability', () => {
    process.env.ASSET_CHECK_ENABLED = 'true';
    expect(() => assetSelectionQuery({ sort: 'checked_asc' })).toThrow(
      'Invalid selection sort',
    );
    expect(() =>
      assetSelectionV2Query({ sort: 'checked_asc', checkMode: 'all' }),
    ).toThrow('Invalid selection sort');
  });
});
