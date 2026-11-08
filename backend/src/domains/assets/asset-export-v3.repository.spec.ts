jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import { AssetExportV3Module } from './asset-export-v3.module';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetExportV3Repository } from './asset-export-v3.repository';

const owner = '507f1f77bcf86cd799439011';
describe('v3 snapshot SQL contracts (offline)', () => {
  const query = jest.fn();
  const repository = new AssetExportV3Repository({
    pool: { query },
  } as unknown as PostgresDatabase);
  beforeEach(() => query.mockReset());
  it('rejects invalid owner before SQL', async () => {
    await expect(repository.exportSnapshot('invalid')).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).not.toHaveBeenCalled();
  });
  it('uses one owner-scoped statement with an overflow sentinel and explicit fields', async () => {
    const snapshot = { exportedAt: '2026-10-27T08:00:00Z', records: [] };
    query.mockResolvedValue({ rows: [snapshot] });
    expect(await repository.exportSnapshot(owner.toUpperCase())).toEqual(
      snapshot,
    );
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, args] = query.mock.calls[0];
    expect(args).toEqual([owner, 501]);
    expect(sql).toContain('statement_timestamp()');
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('version,location,');
    expect(sql).toContain('purchased_on');
    expect(sql).toContain('warranty_expires_on');
    expect(sql).toContain('ORDER BY updated_at DESC,id DESC LIMIT $2');
    expect(sql).not.toContain('SELECT *');
  });
  it('refuses missing result instead of returning a complete empty snapshot', async () => {
    query.mockResolvedValue({ rows: [] });
    await expect(repository.exportSnapshot(owner)).rejects.toThrow(
      'asset_snapshot_missing',
    );
  });
  it('propagates missing-schema readiness failure without retry or migration', async () => {
    const failure = new Error('synthetic missing location column');
    query.mockRejectedValue(failure);
    const module = new AssetExportV3Module(repository);
    await expect(module.onModuleInit()).rejects.toBe(failure);
    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0][0]).toMatch(/^SELECT .* LIMIT 0$/);
  });
  it('propagates snapshot failure without returning empty success or retrying', async () => {
    const failure = new Error('synthetic snapshot unavailable');
    query.mockRejectedValue(failure);
    await expect(repository.exportSnapshot(owner)).rejects.toBe(failure);
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('only reads prerequisites at startup', async () => {
    query.mockResolvedValue({ rows: [] });
    await repository.ready();
    expect(query.mock.calls[0][0]).toBe(
      'SELECT id,owner_id,location,purchased_on,warranty_expires_on FROM assets.assets LIMIT 0',
    );
  });
});
