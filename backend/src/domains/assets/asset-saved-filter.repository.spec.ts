import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetSavedFilterRepository } from './asset-saved-filter.repository';

const owner = '507f1f77bcf86cd799439011';
const query = {
  q: '%_',
  status: '',
  category: '',
  sort: 'updated_desc',
  locationMode: 'all',
  location: '',
  warranty: 'all',
  asOf: '',
  checkMode: 'all',
  checkBefore: '',
  checkOnOrAfter: '',
};
function fixture(total = 0) {
  const calls: string[] = [];
  const execute = jest.fn(
    async (
      sql: string,
      _values?: unknown[],
    ): Promise<{ rows: Record<string, unknown>[] }> => {
      calls.push(sql);
      if (sql.includes('FOR UPDATE')) return { rows: [{ id: owner }] };
      if (sql.includes('count(*)')) return { rows: [{ total }] };
      if (sql.includes('INSERT')) return { rows: [{ id: 'new', query }] };
      return { rows: [] };
    },
  );
  const release = jest.fn();
  const connect = jest.fn(async () => ({ query: execute, release }));
  const database = {
    pool: { connect, query: execute },
  } as unknown as PostgresDatabase;
  return {
    repository: new AssetSavedFilterRepository(database),
    execute,
    connect,
    release,
    calls,
  };
}
describe('saved filter repository offline contracts', () => {
  it('locks the actual owner before counting and committing a definition', async () => {
    const f = fixture();
    await f.repository.create(owner, 'My view', query);
    expect(f.calls.map((sql) => sql.split(' ')[0])).toEqual([
      'BEGIN',
      'SELECT',
      'SELECT',
      'INSERT',
      'COMMIT',
    ]);
    expect(f.calls[1]).toContain('FOR UPDATE');
    expect(f.execute.mock.calls[1]).toEqual([expect.any(String), [owner]]);
    expect(f.release).toHaveBeenCalledTimes(1);
    expect(f.calls.join(' ')).not.toContain('UPDATE assets.assets');
  });
  it('rolls back at capacity without insert', async () => {
    const f = fixture(20);
    await expect(f.repository.create(owner, 'My view', query)).rejects.toThrow(
      'limit',
    );
    expect(f.calls.at(-1)).toBe('ROLLBACK');
    expect(f.calls.some((sql) => sql.startsWith('INSERT'))).toBe(false);
    expect(f.release).toHaveBeenCalledTimes(1);
  });
  it('rejects malformed input before connecting', async () => {
    const f = fixture();
    await expect(f.repository.create(owner, 'My view', {})).rejects.toThrow();
    expect(f.connect).not.toHaveBeenCalled();
  });
  it('does not retry commit failure and always releases', async () => {
    const f = fixture();
    f.execute.mockImplementation(async (sql) => {
      if (sql === 'COMMIT') throw new Error('connection lost');
      if (sql.includes('FOR UPDATE')) return { rows: [{ id: owner }] };
      if (sql.includes('count(*)')) return { rows: [{ total: 0 }] };
      if (sql.startsWith('INSERT')) return { rows: [{ id: 'new' }] };
      return { rows: [] };
    });
    await expect(f.repository.create(owner, 'My view', query)).rejects.toThrow(
      'connection lost',
    );
    expect(f.connect).toHaveBeenCalledTimes(1);
    expect(f.release).toHaveBeenCalledTimes(1);
  });
});

describe('saved filter versioned mutations', () => {
  it.each([true, false])(
    'scopes update/delete before version inspection: update=%s',
    async (update) => {
      const f = fixture();
      f.execute.mockResolvedValue({ rows: [] });
      await expect(
        f.repository.change(
          owner,
          'id',
          1,
          update ? { name: 'View', query } : undefined,
        ),
      ).rejects.toThrow('unavailable');
      expect(f.execute.mock.calls[1]).toEqual([
        expect.stringContaining('WHERE owner_id=$1 AND id=$2 FOR UPDATE'),
        [owner, 'id'],
      ]);
      expect(
        f.execute.mock.calls.some(
          ([sql]) => sql.startsWith('DELETE') || sql.startsWith('UPDATE'),
        ),
      ).toBe(false);
      expect(f.release).toHaveBeenCalledTimes(1);
    },
  );
  it('rejects a stale version without writing', async () => {
    const f = fixture();
    f.execute.mockResolvedValue({ rows: [{ version: 2 }] });
    await expect(f.repository.change(owner, 'id', 1)).rejects.toThrow(
      'changed',
    );
    expect(f.execute.mock.calls.some(([sql]) => sql.startsWith('DELETE'))).toBe(
      false,
    );
  });
  it.each([0, -1, 1.5, 2147483648])(
    'rejects invalid version %s before connection',
    async (version) => {
      const f = fixture();
      await expect(f.repository.change(owner, 'id', version)).rejects.toThrow(
        'version',
      );
      expect(f.connect).not.toHaveBeenCalled();
    },
  );
});

describe('saved filter owned mutation success and listing', () => {
  it.each([true, false])(
    'commits a versioned mutation without asset writes: update=%s',
    async (update) => {
      const f = fixture();
      f.execute.mockImplementation(async (sql) => {
        if (sql.includes('FOR UPDATE')) return { rows: [{ version: 1 }] };
        if (sql.startsWith('UPDATE') || sql.startsWith('DELETE'))
          return { rows: [{ id: 'id', version: 2 }] };
        return { rows: [] };
      });
      await f.repository.change(
        owner,
        'id',
        1,
        update ? { name: 'View', query } : undefined,
      );
      const calls = f.execute.mock.calls;
      expect(calls.map(([sql]) => sql.split(' ')[0])).toEqual([
        'BEGIN',
        'SELECT',
        update ? 'UPDATE' : 'DELETE',
        'COMMIT',
      ]);
      expect(calls[2][0]).toContain('WHERE owner_id=$1 AND id=$2');
      expect(calls[2][1]?.slice(0, 2)).toEqual([owner, 'id']);
      expect(calls[2][0]).not.toContain('assets.assets');
      expect(f.release).toHaveBeenCalledTimes(1);
    },
  );
  it('bounds listing and refuses capacity corruption', async () => {
    const f = fixture();
    f.execute.mockResolvedValue({
      rows: Array.from({ length: 21 }, () => ({})),
    });
    await expect(f.repository.list(owner)).rejects.toThrow('capacity');
    expect(f.execute.mock.calls[0]).toEqual([
      expect.stringContaining('WHERE owner_id=$1'),
      [owner],
    ]);
    expect(f.execute.mock.calls[0][0]).toContain('LIMIT 21');
  });
});

describe('maximum version deletion and result invariants', () => {
  it('allows deleting a terminal-version definition without incrementing it', async () => {
    const f = fixture();
    f.execute.mockImplementation(async (sql) => {
      if (sql.includes('FOR UPDATE'))
        return { rows: [{ version: 2147483647 }] };
      if (sql.startsWith('DELETE')) return { rows: [{ id: 'id' }] };
      return { rows: [] };
    });
    await expect(f.repository.change(owner, 'id', 2147483647)).resolves.toEqual(
      { id: 'id' },
    );
  });
  it('refuses a replacement that would overflow its integer version', async () => {
    const f = fixture();
    await expect(
      f.repository.change(owner, 'id', 2147483647, { name: 'View', query }),
    ).rejects.toThrow('version');
    expect(f.connect).not.toHaveBeenCalled();
  });
});
