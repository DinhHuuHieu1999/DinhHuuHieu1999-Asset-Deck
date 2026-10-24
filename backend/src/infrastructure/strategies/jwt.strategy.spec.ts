import { UnauthorizedException } from '@nestjs/common';
import { statusAuthEnum } from '../../shared/enums/status-auth.enum';
import { JwtStrategy } from './jwt.strategy';

jest.mock('jose', () => ({ jwtVerify: jest.fn() }));

describe('JwtStrategy.validate', () => {
  function createStrategy(user: unknown) {
    const findById = jest.fn().mockResolvedValue(user);
    const configService = { get: jest.fn().mockReturnValue('test-secret') };

    return {
      strategy: new JwtStrategy(configService as never, { findById } as never),
      findById,
    };
  }

  it('uses current database role and email instead of stale token claims', async () => {
    const { strategy } = createStrategy({
      email: 'current@example.com',
      username: 'current.user',
      name: 'Current User',
      role: 'USER',
      status: statusAuthEnum.ACTIVE,
      requireReverify: false,
    });

    await expect(
      strategy.validate({
        sub: 'user-1',
        role: 'ADMINISTRATOR',
        email: 'old@example.com',
      }),
    ).resolves.toEqual({
      userId: 'user-1',
      role: 'USER',
      email: 'current@example.com',
      username: 'current.user',
      name: 'Current User',
    });
  });

  it.each([
    ['missing account', null],
    [
      'inactive account',
      { status: statusAuthEnum.INACTIVE, requireReverify: false },
    ],
    [
      'account requiring verification',
      { status: statusAuthEnum.ACTIVE, requireReverify: true },
    ],
  ])('rejects a token for a %s', async (_label, user) => {
    const { strategy } = createStrategy(user);

    await expect(
      strategy.validate({ sub: 'user-1', role: 'USER' }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
