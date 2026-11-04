import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetsRepository } from './assets.repository';
import { AssetDatesRepository } from './asset-dates.repository';
import { AssetLocationRepository } from './asset-location.repository';
import { AssetQueryDto } from './assets.dto';
import { AssetWarrantyQueryDto } from './asset-warranty.dto';
import { assetCheckPredicate } from './asset-check';

const owner = '507f1f77bcf86cd799439011';
describe('unchecked inventory filter before pagination', () => {
  const query = jest.fn().mockResolvedValue({ rows: [] });
  const database = { pool: { query } } as unknown as PostgresDatabase;
  const original = process.env.ASSET_CHECK_ENABLED;
  beforeEach(() => {
    query.mockClear();
    delete process.env.ASSET_CHECK_ENABLED;
  });
  afterEach(() => {
    if (original === undefined) delete process.env.ASSET_CHECK_ENABLED;
    else process.env.ASSET_CHECK_ENABLED = original;
  });
  it('legacy mode never references the optional column', async () => {
    await new AssetsRepository(database).list(owner, new AssetQueryDto());
    expect(query.mock.calls[0][0]).not.toContain('last_checked_on');
  });
  it('rejects disabled or invalid modes before querying', async () => {
    await expect(
      new AssetsRepository(database).list(
        owner,
        Object.assign(new AssetQueryDto(), { checkMode: 'unchecked' }),
      ),
    ).rejects.toThrow('unavailable');
    expect(() => assetCheckPredicate('unchecked OR true')).toThrow(
      'Invalid check filter',
    );
    expect(query).not.toHaveBeenCalled();
  });
  it('DTO rejects repeated/unknown modes rather than coercing them', async () => {
    for (const checkMode of ['checked', '', ['all', 'unchecked']]) {
      expect(
        await validate(plainToInstance(AssetQueryDto, { checkMode })),
      ).not.toHaveLength(0);
    }
  });
  it.each(['base', 'warranty', 'location'] as const)(
    'combines %s scope with NULL before LIMIT/OFFSET',
    async (kind) => {
      process.env.ASSET_CHECK_ENABLED = 'true';
      const input = Object.assign(new AssetQueryDto(), {
        checkMode: 'unchecked',
        q: '%_',
        status: 'stored',
        category: 'fixture',
        offset: 50,
      });
      if (kind === 'base')
        await new AssetsRepository(database).list(owner, input);
      else if (kind === 'warranty')
        await new AssetDatesRepository(database).warrantyList(
          owner,
          Object.assign(new AssetWarrantyQueryDto(), input),
          { filter: 'expired', asOf: '2026-10-31', through: '2026-11-30' },
        );
      else
        await new AssetLocationRepository(database).list(owner, input, {
          mode: 'exact',
          location: '%_Room',
        });
      const [sql, params] = query.mock.calls[0];
      expect(sql).toContain('owner_id=$1');
      expect(sql).toContain('AND last_checked_on IS NULL');
      expect(sql.indexOf('last_checked_on IS NULL')).toBeLessThan(
        sql.indexOf('LIMIT 51 OFFSET $2'),
      );
      expect(params.slice(0, 5)).toEqual([
        owner,
        50,
        '%_',
        'stored',
        'fixture',
      ]);
      expect(query).toHaveBeenCalledTimes(1);
    },
  );
});
