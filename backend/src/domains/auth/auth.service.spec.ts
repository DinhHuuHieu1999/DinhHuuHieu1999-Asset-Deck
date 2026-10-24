import { roleAuthEnum } from '../../shared/enums/role-auth.enum';
import { statusAuthEnum } from '../../shared/enums/status-auth.enum';
import { AuthService } from './auth.service';
import { escapeRegExp } from './auth-search.util';

jest.mock('jose', () => ({ SignJWT: jest.fn() }));

describe('escapeRegExp', () => {
  it('escapes every regular-expression metacharacter in search input', () => {
    const escaped = escapeRegExp('john.*(admin)+');

    expect(escaped).toBe('john\\.\\*\\(admin\\)\\+');
  });
});

describe('AuthService.listUsers', () => {
  it('returns only minimal directory fields for active users', async () => {
    const find = jest.fn().mockResolvedValue([
      {
        id: 'user-1',
        username: 'guest',
        name: 'Guest User',
        role: 'USER',
        email: 'private@example.com',
        lastLoginAt: new Date(),
      },
    ]);
    const service = new AuthService({ find } as never, {} as never);

    await expect(service.listUsers()).resolves.toEqual({
      users: [
        { id: 'user-1', username: 'guest', name: 'Guest User', role: 'USER' },
      ],
    });
    expect(find).toHaveBeenCalledWith(
      { status: statusAuthEnum.ACTIVE },
      { sort: 'name' },
    );
  });
});

describe('AuthService.forgotPassword', () => {
  it('normalizes the email before querying account storage', async () => {
    const findByEmail = jest.fn().mockResolvedValue(null);
    const service = new AuthService({ findByEmail } as never, {} as never);

    await expect(
      service.forgotPassword({ email: ' User@Example.com ' }),
    ).resolves.toEqual({
      message: 'If the email exists, reset instructions were issued',
    });
    expect(findByEmail).toHaveBeenCalledWith('user@example.com');
  });
});

describe('AuthService.getDashboardSummary', () => {
  it('limits a regular user to their own account summary', async () => {
    const now = new Date();
    const findById = jest.fn().mockResolvedValue({
      id: 'user-1',
      username: 'guest',
      name: 'Guest User',
      role: 'USER',
      status: statusAuthEnum.ACTIVE,
      createdAt: now,
      updatedAt: now,
      lastLoginAt: now,
    });
    const count = jest.fn();
    const service = new AuthService({ findById, count } as never, {} as never);

    const result = await service.getDashboardSummary(
      'user-1',
      roleAuthEnum.USER,
    );

    expect(findById).toHaveBeenCalledWith('user-1');
    expect(count).not.toHaveBeenCalled();
    expect(result.metrics).toEqual({
      activeAccounts: 1,
      administrators: 0,
      recentLogins: 1,
      newAccounts: 1,
    });
    expect(result.recentAccounts).toHaveLength(1);
    expect(result.recentAccounts[0]).toMatchObject({
      id: 'user-1',
      username: 'guest',
    });
  });

  it('keeps aggregate account metrics available to administrators', async () => {
    const count = jest
      .fn()
      .mockResolvedValueOnce(12)
      .mockResolvedValueOnce(2)
      .mockResolvedValueOnce(7)
      .mockResolvedValueOnce(3);
    const find = jest.fn().mockResolvedValue([]);
    const findById = jest.fn();
    const service = new AuthService(
      { count, find, findById } as never,
      {} as never,
    );

    const result = await service.getDashboardSummary(
      'admin-1',
      roleAuthEnum.ADMINISTRATOR,
    );

    expect(findById).not.toHaveBeenCalled();
    expect(result.metrics).toEqual({
      activeAccounts: 12,
      administrators: 2,
      recentLogins: 7,
      newAccounts: 3,
    });
  });
});
