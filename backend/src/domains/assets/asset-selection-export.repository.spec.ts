import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetSelectionExportRepository } from './asset-selection-export.repository';
import type { AssetSelectionScope } from './asset-selection-export';

const owner = '507f1f77bcf86cd799439011';
const scope: AssetSelectionScope = {
  q: '%_',
  status: 'stored',
  category: 'fixture',
  locationMode: 'exact',
  location: 'Room %_1',
  sort: 'name_asc',
  warranty: {
    filter: 'expiring_soon',
    asOf: '2026-10-29',
    through: '2026-11-28',
  },
};
describe('selection snapshot SQL contract (offline)', () => {
  const query = jest.fn();
  const repository = new AssetSelectionExportRepository({
    pool: { query },
  } as unknown as PostgresDatabase);
  beforeEach(() => query.mockReset());
  it('uses one snapshot, all predicates before the 501 sentinel, no page offset', async () => {
    const snapshot = { exportedAt: '2026-10-29T00:00:00Z', records: [] };
    query.mockResolvedValue({ rows: [snapshot] });
    expect(await repository.exportSnapshot(owner.toUpperCase(), scope)).toBe(
      snapshot,
    );
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, args] = query.mock.calls[0];
    expect(args).toEqual([
      owner,
      501,
      '%_',
      'stored',
      'fixture',
      'exact',
      'Room %_1',
      'expiring_soon',
      '2026-10-29',
      '2026-11-28',
    ]);
    expect(sql).toContain('statement_timestamp()');
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('strpos(lower(name),lower($3))');
    expect(sql).toContain('location=$7');
    expect(sql).toContain('warranty_expires_on <= $10::date');
    expect(sql).toContain('ORDER BY name COLLATE "C" ASC,id ASC LIMIT $2');
    expect(sql).not.toMatch(/OFFSET|SELECT \*|ILIKE/);
  });
  it('binds unknown location and no warranty explicitly', async () => {
    query.mockResolvedValue({ rows: [{ records: [] }] });
    await repository.exportSnapshot(owner, {
      ...scope,
      locationMode: 'unknown',
      location: null,
      warranty: null,
      sort: 'updated_desc',
    });
    expect(query.mock.calls[0][1].slice(5)).toEqual([
      'unknown',
      null,
      '',
      null,
      null,
    ]);
    expect(query.mock.calls[0][0]).toContain(
      'ORDER BY updated_at DESC,id DESC',
    );
  });
  it('rejects invalid owner or scope before SQL', async () => {
    await expect(repository.exportSnapshot('invalid', scope)).rejects.toThrow();
    await expect(
      repository.exportSnapshot(owner, { ...scope, sort: 'unsafe' as never }),
    ).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
  });
  it('does not convert missing result or SQL failure into empty success', async () => {
    query.mockResolvedValue({ rows: [] });
    await expect(repository.exportSnapshot(owner, scope)).rejects.toThrow(
      'asset_snapshot_missing',
    );
    query.mockRejectedValue(new Error('synthetic failure'));
    await expect(repository.exportSnapshot(owner, scope)).rejects.toThrow(
      'synthetic failure',
    );
    expect(query).toHaveBeenCalledTimes(2);
  });
});
