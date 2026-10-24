import { BadRequestException, NotFoundException } from '@nestjs/common';
import { PostgresAccountRepository } from './postgres-account.repository';

const ID = '507f1f77bcf86cd799439011';
const row = {
  id: ID,
  email: 'user@example.com',
  username: 'user',
  name: 'User',
  passwordHash: 'bcrypt-hash',
  role: 'USER',
  status: 'ACTIVE',
  failedLoginAttempts: 0,
  lockLevel: 0,
  requireReverify: false,
  resetPasswordTokenHash: 'reset-hash',
  resetPasswordExpiresAt: new Date('2026-11-01'),
  createdAt: new Date('2026-10-01'),
  updatedAt: new Date('2026-10-01'),
};

describe('PostgresAccountRepository', () => {
  function setup() {
    const query = jest
      .fn()
      .mockResolvedValue({ rows: [{ ...row }], rowCount: 1 });
    const repository = new PostgresAccountRepository({
      pool: { query },
    } as never);
    return { repository, query };
  }

  it('keeps account identifiers compatible and ignores malformed subjects', async () => {
    const { repository, query } = setup();
    await expect(repository.findById('unsafe-id')).resolves.toBeNull();
    expect(query).not.toHaveBeenCalled();
    await repository.findById(ID.toUpperCase());
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('WHERE id = $1'),
      [ID],
    );
  });

  it('binds identity, email and reset-token parameters without SQL interpolation', async () => {
    const { repository, query } = setup();
    const injection = "name' OR true --";
    await repository.findByIdentity(injection, injection);
    expect(query).toHaveBeenLastCalledWith(
      expect.stringContaining('email = $1 OR username = $2'),
      [injection, injection],
    );
    expect(query.mock.calls[0]?.[0]).not.toContain(injection);
    await repository.findByEmail(injection);
    expect(query).toHaveBeenLastCalledWith(
      expect.stringContaining('email = $1'),
      [injection],
    );
    const now = new Date();
    await repository.findByResetToken('hashed-token', now);
    expect(query).toHaveBeenLastCalledWith(
      expect.stringContaining('reset_password_expires_at > $2'),
      ['hashed-token', now],
    );
  });

  it('normalizes nullable SQL fields to optional account state', async () => {
    const { repository, query } = setup();
    query.mockResolvedValue({
      rows: [{ ...row, lockUntil: null, resetPasswordTokenHash: null }],
    });
    const account = await repository.findById(ID);
    expect(account?.lockUntil).toBeUndefined();
    expect(account?.resetPasswordTokenHash).toBeUndefined();
  });

  it('creates an account with a stable 24-hex ID and bound values', async () => {
    const { repository, query } = setup();
    await repository.create({
      email: row.email,
      username: row.username,
      name: row.name,
      passwordHash: row.passwordHash,
      role: 'USER',
      status: 'ACTIVE',
    });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO auth.accounts'),
      [
        expect.stringMatching(/^[0-9a-f]{24}$/),
        row.email,
        row.username,
        row.name,
        row.passwordHash,
        'USER',
        'ACTIVE',
      ],
    );
  });

  it.each([
    ['accounts_email_key', 'Email already exists'],
    ['accounts_username_key', 'Username already exists'],
  ])(
    'maps uniqueness constraint %s to the existing public error',
    async (constraint, message) => {
      const { repository, query } = setup();
      query.mockRejectedValue({ code: '23505', constraint });
      await expect(
        repository.create({
          email: row.email,
          username: row.username,
          name: row.name,
          passwordHash: row.passwordHash,
          role: 'USER',
          status: 'ACTIVE',
        }),
      ).rejects.toThrow(new BadRequestException(message));
    },
  );

  it('writes only changed fields and binds cleared credentials as NULL', async () => {
    const { repository, query } = setup();
    const account = await repository.findById(ID);
    if (!account) throw new Error('Fixture missing');
    account.passwordHash = 'new-hash';
    account.resetPasswordTokenHash = undefined;
    account.resetPasswordExpiresAt = undefined;
    await repository.save(account);
    expect(query).toHaveBeenLastCalledWith(
      'UPDATE auth.accounts SET password_hash = $1, reset_password_token_hash = $2, reset_password_expires_at = $3, updated_at = $4 WHERE id = $5',
      ['new-hash', null, null, expect.any(Date), ID],
    );
    await repository.save(account);
    expect(query).toHaveBeenCalledTimes(2);
  });

  it('reports missing accounts instead of accepting a lost update', async () => {
    const { repository, query } = setup();
    const account = await repository.findById(ID);
    if (!account) throw new Error('Fixture missing');
    account.status = 'SUSPENDED';
    query.mockResolvedValue({ rowCount: 0 });
    await expect(repository.save(account)).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('binds literal search characters and pagination, allowlisting sorting', async () => {
    const { repository, query } = setup();
    const search = "'_%.* --";
    await repository.find(
      { status: 'ACTIVE', search },
      { sort: 'updatedAt', limit: 20, skip: 40 },
    );
    expect(query).toHaveBeenLastCalledWith(
      expect.stringContaining('ORDER BY updated_at DESC LIMIT $3 OFFSET $4'),
      ['ACTIVE', search, 20, 40],
    );
    expect(query.mock.calls[0]?.[0]).not.toContain(search);
    expect(query.mock.calls[0]?.[0]).toContain('strpos');
    await expect(
      repository.find({}, { sort: 'untrusted' as never }),
    ).rejects.toThrow('Invalid account sort');
    expect(query).toHaveBeenCalledTimes(1);
  });

  it('counts with parameterized date filters and checks numeric precision', async () => {
    const { repository, query } = setup();
    const date = new Date();
    query.mockResolvedValue({ rows: [{ total: '12' }] });
    await expect(
      repository.count({
        role: 'USER',
        lastLoginSince: date,
        createdSince: date,
      }),
    ).resolves.toBe(12);
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('last_login_at >= $2 AND created_at >= $3'),
      ['USER', date, date],
    );
    query.mockResolvedValue({ rows: [{ total: '9007199254740992' }] });
    await expect(repository.count({})).rejects.toThrow('Invalid account count');
  });
});
