import { AssetExportV4Repository } from './asset-export-v4.repository';

/** SQL contract tests use mocked persistence, never a real database. */
describe('full v4 repository contracts', () => {
  const owner = '507f1f77bcf86cd799439011';
  it('reads one owner statement with a 501-row sentinel and manual date', async () => {
    const snapshot = { exportedAt: '2026-11-05T00:00:00Z', records: [] };
    const query = jest.fn().mockResolvedValue({ rows: [snapshot] });
    const repository = new AssetExportV4Repository({
      pool: { query },
    } as never);
    expect(await repository.exportSnapshot(owner.toUpperCase())).toBe(snapshot);
    expect(query).toHaveBeenCalledTimes(1);
    const [sql, args] = query.mock.calls[0];
    expect(args).toEqual([owner, 501]);
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('ORDER BY updated_at DESC,id DESC LIMIT $2');
    expect(sql).toContain('to_char(last_checked_on');
    expect(sql).not.toMatch(/check_version|\b(?:INSERT|UPDATE|DELETE)\b/i);
  });
  it('rejects invalid owners before SQL and missing snapshots', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new AssetExportV4Repository({
      pool: { query },
    } as never);
    await expect(repository.exportSnapshot('other')).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
    await expect(repository.exportSnapshot(owner)).rejects.toThrow(
      'asset_snapshot_missing',
    );
  });
  it('readiness checks the existing check column and propagates errors', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const repository = new AssetExportV4Repository({
      pool: { query },
    } as never);
    await repository.ready();
    expect(query.mock.calls[0][0]).toContain('last_checked_on');
    query.mockRejectedValue(new Error('missing schema'));
    await expect(repository.ready()).rejects.toThrow('missing schema');
  });
});
