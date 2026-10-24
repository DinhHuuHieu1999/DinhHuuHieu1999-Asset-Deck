import { Pool } from 'pg';
import { PostgresDatabase } from './postgres.database';

jest.mock('pg', () => ({ Pool: jest.fn() }));

describe('PostgresDatabase lifecycle', () => {
  const original = { ...process.env };
  const query = jest.fn();
  const end = jest.fn();
  const on = jest.fn();
  beforeEach(() => {
    jest.clearAllMocks();
    process.env.AUTH_POSTGRES_URL = 'postgresql://fixture@127.0.0.1/fixture';
    delete process.env.AUTH_POSTGRES_POOL_SIZE;
    delete process.env.AUTH_POSTGRES_CONNECT_TIMEOUT_MS;
    delete process.env.AUTH_POSTGRES_STATEMENT_TIMEOUT_MS;
    query.mockResolvedValue({ rows: [] });
    end.mockResolvedValue(undefined);
    jest
      .mocked(Pool)
      .mockImplementation(() => ({ query, end, on }) as unknown as Pool);
  });
  afterEach(() => {
    for (const key of [
      'AUTH_POSTGRES_URL',
      'AUTH_POSTGRES_POOL_SIZE',
      'AUTH_POSTGRES_CONNECT_TIMEOUT_MS',
      'AUTH_POSTGRES_STATEMENT_TIMEOUT_MS',
    ]) {
      if (original[key] === undefined) delete process.env[key];
      else process.env[key] = original[key];
    }
  });

  it('requires an explicit connection instead of falling back to a local or MongoDB store', () => {
    delete process.env.AUTH_POSTGRES_URL;
    expect(() => new PostgresDatabase()).toThrow('AUTH_POSTGRES_URL');
    expect(Pool).not.toHaveBeenCalled();
  });

  it('sets bounded pool, connection and statement limits without weakening TLS checks', () => {
    const database = new PostgresDatabase();
    expect(Pool).toHaveBeenCalledWith({
      connectionString: process.env.AUTH_POSTGRES_URL,
      max: 10,
      connectionTimeoutMillis: 5000,
      idleTimeoutMillis: 30000,
      statement_timeout: 5000,
      application_name: 'asset-desk-auth',
    });
    expect(database.pool).toBeDefined();
  });

  it.each([
    'not-a-url',
    'https://example.com/accounts',
    'postgresql://127.0.0.1',
  ])('rejects incomplete or incorrect connection URLs: %s', (value) => {
    process.env.AUTH_POSTGRES_URL = value;
    expect(() => new PostgresDatabase()).toThrow('explicit host and database');
    expect(Pool).not.toHaveBeenCalled();
  });

  it.each(['0', '-1', '2.5', 'not-a-number'])(
    'rejects invalid pool size %s',
    (value) => {
      process.env.AUTH_POSTGRES_POOL_SIZE = value;
      expect(() => new PostgresDatabase()).toThrow('AUTH_POSTGRES_POOL_SIZE');
    },
  );

  it('drains owned background work before closing the pool', async () => {
    const database = new PostgresDatabase();
    const task = jest.fn().mockImplementation(() => {
      expect(end).not.toHaveBeenCalled();
      return Promise.resolve();
    });
    database.beforePoolClose(task);
    await database.onModuleDestroy();
    expect(task).toHaveBeenCalledTimes(1);
    expect(end).toHaveBeenCalledTimes(1);
  });

  it('checks schema availability without running migrations or reading account rows', async () => {
    const database = new PostgresDatabase();
    await database.onModuleInit();
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('FROM auth.accounts LIMIT 0'),
    );
    expect(query.mock.calls[0]?.[0]).not.toMatch(/CREATE|INSERT|UPDATE/);
    await expect(database.isReady()).resolves.toBe(true);
    query.mockRejectedValue(new Error('connection failed'));
    await expect(database.isReady()).resolves.toBe(false);
    await expect(database.onModuleInit()).rejects.toThrow('connection failed');
    await database.onModuleDestroy();
    expect(end).toHaveBeenCalledTimes(1);
  });
});
