import { AssetDatesRepository } from './asset-dates.repository';
import { AssetLocationRepository } from './asset-location.repository';
import { AssetWarrantyQueryDto } from './asset-warranty.dto';
import { AssetsRepository } from './assets.repository';
import { AssetQueryDto } from './assets.dto';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';

const owner = '507f1f77bcf86cd799439011';
describe('checked-before parameter boundary', () => {
  const query = jest.fn().mockResolvedValue({ rows: [] });
  const database = { pool: { query } } as unknown as PostgresDatabase;
  const original = process.env.ASSET_CHECK_ENABLED;
  beforeEach(() => {
    query.mockClear();
    process.env.ASSET_CHECK_ENABLED = 'true';
  });
  afterEach(() => {
    if (original === undefined) delete process.env.ASSET_CHECK_ENABLED;
    else process.env.ASSET_CHECK_ENABLED = original;
  });
  it('binds a strict less-than date before pagination without interpolating it', async () => {
    await new AssetsRepository(database).list(
      owner,
      Object.assign(new AssetQueryDto(), {
        checkMode: 'before',
        checkBefore: '2024-02-29',
      }),
    );
    const [sql, values] = query.mock.calls[0];
    expect(sql).toContain('AND last_checked_on < $6::date');
    expect(sql).not.toContain('2024-02-29');
    expect(sql.indexOf('last_checked_on <')).toBeLessThan(
      sql.indexOf('LIMIT 51'),
    );
    expect(values).toEqual([owner, 0, '', '', '', '2024-02-29']);
  });
  it.each(['warranty', 'location', 'combined'])(
    'binds cutoff after existing %s parameters',
    async (kind) => {
      const input = Object.assign(new AssetWarrantyQueryDto(), {
        checkMode: 'before',
        checkBefore: '2024-02-29',
        offset: 50,
      });
      const window = {
        filter: 'expired' as const,
        asOf: '2026-11-04',
        through: '2026-12-04',
      };
      if (kind === 'warranty')
        await new AssetDatesRepository(database).warrantyList(
          owner,
          input,
          window,
        );
      else
        await new AssetLocationRepository(database).list(
          owner,
          input,
          { mode: 'exact', location: '%_room' },
          kind === 'combined' ? window : undefined,
        );
      const [sql, values] = query.mock.calls[0];
      const index = kind === 'warranty' ? 9 : kind === 'combined' ? 11 : 8;
      expect(sql).toContain(`AND last_checked_on < $${index}::date`);
      expect(values).toHaveLength(index);
      expect(values[index - 1]).toBe('2024-02-29');
      expect(values[0]).toBe(owner);
      expect(values[1]).toBe(50);
    },
  );
  it.each([
    '',
    '2023-02-29',
    '2024-02-29 ',
    '0000-01-01',
    '2024-01-01T00:00:00Z',
    ['2024-02-29'],
  ])('rejects malformed cutoff before SQL: %p', async (checkBefore) => {
    await expect(
      new AssetsRepository(database).list(
        owner,
        Object.assign(new AssetQueryDto(), {
          checkMode: 'before',
          checkBefore,
        }),
      ),
    ).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
  });
  it.each(['all', 'unchecked'])(
    'rejects stray cutoff in %s mode',
    async (checkMode) => {
      await expect(
        new AssetsRepository(database).list(
          owner,
          Object.assign(new AssetQueryDto(), {
            checkMode,
            checkBefore: '2024-02-29',
          }),
        ),
      ).rejects.toThrow();
      expect(query).not.toHaveBeenCalled();
    },
  );
});
