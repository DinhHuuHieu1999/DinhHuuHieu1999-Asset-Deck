import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { JwtStrategy } from '../../infrastructure/strategies/jwt.strategy';
import { AccountRepository, isAccountId } from './account.repository';
import { AuthService } from './auth.service';

const ID = '507f1f77bcf86cd799439011';
jest.mock('jose', () => ({
  SignJWT: jest.fn(),
  jwtVerify: jest
    .fn()
    .mockResolvedValue({ payload: { sub: '507f1f77bcf86cd799439011' } }),
}));

describe('Account repository boundary', () => {
  it('retains legacy account identifiers without depending on a MongoDB validator', () => {
    expect(isAccountId(ID)).toBe(true);
    expect(isAccountId(ID.toUpperCase())).toBe(true);
    expect(isAccountId('untrusted-id')).toBe(false);
    expect(isAccountId(`${ID}extra`)).toBe(false);
  });

  it.each([
    '',
    ` ${ID}`,
    `${ID} `,
    `${ID}\n`,
    ID.slice(1),
    `${ID}0`,
    '507f1f77bcf86cd79943901g',
    '5dc1f76f-c0da-4714-aba3-aaefa6d5bec4',
  ])(
    'rejects incompatible account identifier %j without normalization',
    (value) => {
      expect(isAccountId(value)).toBe(false);
    },
  );

  it('resolves HTTP and JWT consumers with the same repository and no ORM provider', async () => {
    const findById = jest.fn().mockResolvedValue({
      id: ID,
      email: 'current@example.com',
      username: 'current',
      name: 'Current User',
      role: 'USER',
      status: 'ACTIVE',
      requireReverify: false,
    });
    const module = await Test.createTestingModule({
      providers: [
        AuthService,
        JwtStrategy,
        { provide: AccountRepository, useValue: { findById } },
        { provide: CACHE_MANAGER, useValue: {} },
        {
          provide: ConfigService,
          useValue: new ConfigService({ JWT_ACCESS_SECRET: 'test-secret' }),
        },
      ],
    }).compile();
    try {
      await expect(
        module.get(AuthService).getProfile(ID),
      ).resolves.toMatchObject({
        user: { id: ID, role: 'USER' },
      });
      await expect(
        module.get(JwtStrategy).validate({ sub: ID, role: 'ADMINISTRATOR' }),
      ).resolves.toMatchObject({ userId: ID, role: 'USER' });
      expect(findById).toHaveBeenCalledTimes(2);
      expect(findById).toHaveBeenNthCalledWith(1, ID);
      expect(findById).toHaveBeenNthCalledWith(2, ID);
    } finally {
      await module.close();
    }
  });
});
