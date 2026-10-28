import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetLocationRepository } from './asset-location.repository';
import { AssetQueryDto } from './assets.dto';

const owner = '507f1f77bcf86cd799439011';
const id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
describe('location persistence offline SQL contracts', () => {
  const query = jest.fn();
  const repository = new AssetLocationRepository({
    pool: { query },
  } as unknown as PostgresDatabase);
  beforeEach(() => {
    query.mockReset();
    query.mockResolvedValue({ rows: [] });
  });
  it('overview groups the entire owner inventory in one bounded statement', async () => {
    query.mockResolvedValue({
      rows: [
        { location: null, count: '2' },
        { location: 'Room %_1', count: '60' },
      ],
    });
    expect(await repository.overview(owner.toUpperCase())).toEqual({
      complete: true,
      total: 62,
      unknown: 2,
      locations: [{ location: 'Room %_1', count: 60 }],
    });
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, args] = query.mock.calls[0];
    expect(args).toEqual([owner]);
    expect(sql).toContain('WHERE owner_id=$1 GROUP BY location');
    expect(sql).toContain('LIMIT 1002');
    expect(sql).not.toMatch(/OFFSET|status=|category=/);
  });
  it('overview refuses invalid owner before reading', async () => {
    await expect(repository.overview('invalid')).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).not.toHaveBeenCalled();
  });
  it('overview propagates SQL failures without retry or false empty counts', async () => {
    query.mockRejectedValue(new Error('unavailable'));
    await expect(repository.overview(owner)).rejects.toThrow('unavailable');
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('readiness only reads required columns', async () => {
    await repository.ready();
    expect(query.mock.calls[0][0]).toBe(
      'SELECT id,owner_id,version,location FROM assets.assets LIMIT 0',
    );
  });
  it('refuses invalid owners before SQL', async () => {
    await expect(repository.read('invalid', id)).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).not.toHaveBeenCalled();
  });
  it('reads one owner and returns absent without probing other owners', async () => {
    expect(await repository.read(owner.toUpperCase(), id)).toBeNull();
    expect(query.mock.calls[0][1]).toEqual([owner, id]);
    expect(query.mock.calls[0][0]).toContain('WHERE owner_id=$1 AND id=$2');
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('atomically changes only location/version/timestamp with expected version', async () => {
    const row = { id, version: 8, location: 'Room A' };
    query.mockResolvedValue({ rows: [row] });
    expect(
      await repository.update(owner, id, { version: 7, location: ' Room A ' }),
    ).toEqual(row);
    expect(query.mock.calls[0][1]).toEqual([owner, id, 7, 'Room A']);
    const sql = query.mock.calls[0][0];
    expect(sql).toContain('owner_id=$1 AND id=$2 AND version=$3');
    expect(sql).not.toMatch(
      /SET (name|category|purchased_on|warranty_expires_on)/,
    );
  });
  it('stale updates return null and do not retry', async () => {
    expect(
      await repository.update(owner, id, { version: 1, location: null }),
    ).toBeNull();
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('parameterizes exact labels and combines all filters before paging', async () => {
    const input = Object.assign(new AssetQueryDto(), {
      q: ' %_ ',
      status: 'stored',
      category: ' device ',
      offset: 50,
    });
    await repository.list(owner, input, { mode: 'exact', location: "%_'Room" });
    const [sql, args] = query.mock.calls[0];
    expect(args).toEqual([
      owner,
      50,
      '%_',
      'stored',
      'device',
      'exact',
      "%_'Room",
    ]);
    expect(sql).not.toContain("%_'Room");
    expect(sql).toContain('location=$7');
    expect(sql.indexOf('location=$7')).toBeLessThan(
      sql.indexOf('LIMIT 51 OFFSET $2'),
    );
    expect(sql).not.toMatch(/\bILIKE\b/);
  });
  it('unknown filter is explicit NULL and next page uses the lookahead row', async () => {
    query.mockResolvedValue({
      rows: Array.from({ length: 51 }, () => ({ id })),
    });
    const result = await repository.list(owner, new AssetQueryDto(), {
      mode: 'unknown',
      location: null,
    });
    expect(result.items).toHaveLength(50);
    expect(result.nextOffset).toBe(50);
    expect(query.mock.calls[0][0]).toContain(
      "$6='unknown' AND location IS NULL",
    );
  });
  it('refuses a truncated traversal instead of false completeness', async () => {
    query.mockResolvedValue({
      rows: Array.from({ length: 51 }, () => ({ id })),
    });
    await expect(
      repository.list(
        owner,
        Object.assign(new AssetQueryDto(), { offset: 100000 }),
        { mode: 'all', location: null },
      ),
    ).rejects.toThrow('Pagination limit');
  });
  it('combines warranty window with location before pagination using bound dates', async () => {
    const window = {
      filter: 'expiring_soon' as const,
      asOf: '2026-10-27',
      through: '2026-11-26',
    };
    const result = await repository.list(
      owner,
      new AssetQueryDto(),
      { mode: 'exact', location: 'Office' },
      window,
    );
    const [sql, args] = query.mock.calls[0];
    expect(args).toEqual([
      owner,
      0,
      '',
      '',
      '',
      'exact',
      'Office',
      'expiring_soon',
      '2026-10-27',
      '2026-11-26',
    ]);
    expect(sql).toContain('warranty_expires_on <= $10::date');
    expect(sql).toContain('AS "purchasedOn"');
    expect(result).toEqual({
      items: [],
      nextOffset: null,
      warranty: 'expiring_soon',
      asOf: window.asOf,
      through: window.through,
    });
  });
  it('does not require date columns when warranty is not selected', async () => {
    await repository.list(owner, new AssetQueryDto(), {
      mode: 'all',
      location: null,
    });
    expect(query.mock.calls[0][0]).not.toContain('warranty_expires_on');
  });
});
