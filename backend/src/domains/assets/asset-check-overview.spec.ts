import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetCheckRepository } from './asset-check.repository';
import { AssetCheckController } from './asset-check.controller';
import { buildAssetCheckOverview } from './asset-check-overview';

describe('manual check overview aggregate', () => {
  const row = { total: '6', unknown: '1', before: '2', onOrAfter: '3' };
  it('returns a complete partition pinned to a strict cutoff', () => {
    expect(buildAssetCheckOverview(row, '2024-02-29')).toEqual({
      complete: true,
      cutoff: '2024-02-29',
      total: 6,
      unknown: 1,
      before: 2,
      onOrAfter: 3,
    });
  });
  it('accepts empty inventory', () => {
    expect(
      buildAssetCheckOverview(
        { total: '0', unknown: '0', before: '0', onOrAfter: '0' },
        '0001-01-01',
      ).total,
    ).toBe(0);
  });
  it.each([
    '',
    '2023-02-29',
    '2024-02-29T00:00:00Z',
    ' 2024-02-29',
    '0000-01-01',
  ])('rejects cutoff %s', (cutoff) => {
    expect(() => buildAssetCheckOverview(row, cutoff)).toThrow();
  });
  it.each(['-1', '01', '1.5', '1e0', '', '9007199254740992', 1, null])(
    'rejects aggregate %#',
    (value) => {
      expect(() =>
        buildAssetCheckOverview(
          { ...row, before: value as string },
          '2024-02-29',
        ),
      ).toThrow();
    },
  );
  it('rejects inconsistent totals', () => {
    expect(() =>
      buildAssetCheckOverview({ ...row, total: '7' }, '2024-02-29'),
    ).toThrow();
  });
  it('rejects overflowing sum', () => {
    expect(() =>
      buildAssetCheckOverview(
        {
          total: '9007199254740991',
          unknown: '9007199254740991',
          before: '1',
          onOrAfter: '0',
        },
        '2024-02-29',
      ),
    ).toThrow();
  });
});

describe('check overview owner and query boundaries', () => {
  const owner = '507f1f77bcf86cd799439011';
  const query = jest.fn();
  const repository = new AssetCheckRepository({
    pool: { query },
  } as unknown as PostgresDatabase);
  const controller = new AssetCheckController(repository);
  beforeEach(() =>
    query.mockReset().mockResolvedValue({
      rows: [{ total: '0', unknown: '0', before: '0', onOrAfter: '0' }],
    }),
  );
  it('binds normalized owner and cutoff in one unpaginated statement', async () => {
    expect(
      (await repository.overview(owner.toUpperCase(), '2024-02-29')).complete,
    ).toBe(true);
    const [sql, values] = query.mock.calls[0];
    expect(values).toEqual([owner, '2024-02-29']);
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('last_checked_on < $2::date');
    expect(sql).toContain('last_checked_on >= $2::date');
    expect(sql).not.toMatch(/LIMIT|OFFSET|2024-02-29|UPDATE|INSERT/);
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('refuses invalid owner and cutoff before SQL', async () => {
    await expect(repository.overview('other', '2024-02-29')).rejects.toThrow();
    await expect(repository.overview(owner, '2023-02-29')).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
  });
  it('requires authentication and exactly one valid cutoff', async () => {
    await expect(
      controller.overview({}, { cutoff: '2024-02-29' }),
    ).rejects.toThrow();
    for (const input of [
      {},
      { cutoff: ['2024-02-29'] },
      { cutoff: '2024-02-29', owner },
      { cutoff: '' },
    ]) {
      await expect(
        controller.overview({ user: { userId: owner } }, input),
      ).rejects.toThrow();
    }
    expect(query).not.toHaveBeenCalled();
  });
  it('refuses missing aggregate and propagates failure without retry', async () => {
    query.mockResolvedValueOnce({ rows: [] });
    await expect(repository.overview(owner, '2024-02-29')).rejects.toThrow(
      'missing_aggregate',
    );
    query.mockRejectedValueOnce(new Error('synthetic failure'));
    await expect(repository.overview(owner, '2024-02-29')).rejects.toThrow(
      'synthetic failure',
    );
    expect(query).toHaveBeenCalledTimes(2);
  });
});
