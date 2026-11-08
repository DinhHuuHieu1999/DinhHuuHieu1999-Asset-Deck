import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetCheckRepository } from './asset-check.repository';
import { AssetCheckController } from './asset-check.controller';

const owner = '507f1f77bcf86cd799439011';
const id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
describe('manual check date offline persistence boundaries', () => {
  const query = jest.fn();
  const repository = new AssetCheckRepository({
    pool: { query },
  } as unknown as PostgresDatabase);
  const controller = new AssetCheckController(repository);
  beforeEach(() => query.mockReset().mockResolvedValue({ rows: [] }));
  it('readiness only probes the required schema', async () => {
    await repository.ready();
    expect(query.mock.calls[0][0]).toContain('last_checked_on');
    expect(query.mock.calls[0][0]).toContain('LIMIT 0');
    expect(query.mock.calls[0][0]).not.toMatch(/ALTER|INSERT|UPDATE/);
  });
  it('normalizes owner and parameterizes read identity', async () => {
    expect(await repository.read(owner.toUpperCase(), id)).toBeNull();
    expect(query.mock.calls[0][1]).toEqual([owner, id]);
    expect(query.mock.calls[0][0]).toContain('WHERE owner_id=$1 AND id=$2');
  });
  it('refuses malformed owner before SQL', async () => {
    await expect(repository.read('bad', id)).rejects.toThrow(
      'invalid_asset_owner',
    );
    await expect(
      repository.update('bad', id, { version: 1, lastCheckedOn: null }),
    ).rejects.toThrow('invalid_asset_owner');
    expect(query).not.toHaveBeenCalled();
  });
  it.each(['2024-02-29', null])(
    'writes only check date/version/timestamp: %s',
    async (lastCheckedOn) => {
      const row = { id, version: 8, lastCheckedOn };
      query.mockResolvedValue({ rows: [row] });
      expect(
        await repository.update(owner, id, { version: 7, lastCheckedOn }),
      ).toEqual(row);
      const [sql, args] = query.mock.calls[0];
      expect(args).toEqual([owner, id, 7, lastCheckedOn]);
      expect(sql).toContain('WHERE owner_id=$1 AND id=$2 AND version=$3');
      expect(sql).toContain(
        'SET last_checked_on=$4::date,version=version+1,updated_at=clock_timestamp()',
      );
      expect(query).toHaveBeenCalledTimes(1);
    },
  );
  it('revalidates update before SQL', async () => {
    await expect(
      repository.update(owner, id, { version: 1, lastCheckedOn: '2025-02-29' }),
    ).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
  });
  it('does not retry a failed write', async () => {
    query.mockRejectedValue(new Error('synthetic connection loss'));
    await expect(
      repository.update(owner, id, { version: 1, lastCheckedOn: null }),
    ).rejects.toThrow('synthetic connection loss');
    expect(query).toHaveBeenCalledTimes(1);
  });
  it('requires valid authentication and refuses all query overrides', async () => {
    await expect(controller.read({}, id, {})).rejects.toThrow('Unauthorized');
    await expect(
      controller.update({}, id, { version: 1, lastCheckedOn: null }, {}),
    ).rejects.toThrow('Unauthorized');
    await expect(
      controller.read({ user: { userId: owner } }, id, { owner }),
    ).rejects.toThrow('query');
    expect(query).not.toHaveBeenCalled();
  });
  it('uses indistinguishable missing/foreign read and stale-write responses', async () => {
    await expect(
      controller.read({ user: { userId: owner } }, id, {}),
    ).rejects.toThrow('Asset is unavailable');
    await expect(
      controller.update(
        { user: { userId: owner } },
        id,
        { version: 1, lastCheckedOn: null },
        {},
      ),
    ).rejects.toThrow('changed or is unavailable');
    expect(query).toHaveBeenCalledTimes(2);
  });
});
