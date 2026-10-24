import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { AppModule } from './app.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AccountRepository } from '../../domains/auth/account.repository';
import { PostgresAccountRepository } from '../../domains/auth/postgres-account.repository';
import { AssetsService } from '../../domains/assets/assets.service';
import { AuthController } from '../../domains/auth/auth.controller';
import { AssetsController } from '../../domains/assets/assets.controller';
import { SystemController } from '../system.controller';

jest.mock('jose', () => ({ SignJWT: jest.fn(), jwtVerify: jest.fn() }));

describe('Asset Desk composition without live storage or network', () => {
  it('resolves PostgreSQL accounts and assets without Mongo/gRPC/ToolDeck providers', async () => {
    const query = jest.fn().mockResolvedValue({ rows: [] });
    const database = {
      pool: { query },
      isReady: jest.fn().mockResolvedValue(true),
    };
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PostgresDatabase)
      .useValue(database)
      .compile();
    try {
      expect(module.get(AccountRepository)).toBeInstanceOf(
        PostgresAccountRepository,
      );
      expect(module.get(AuthController)).toBeDefined();
      expect(module.get(AssetsController)).toBeDefined();
      await module.get(AssetsService).onModuleInit();
      expect(query).toHaveBeenCalledWith(
        expect.stringContaining('assets.assets LIMIT 0'),
      );
      await expect(module.get(SystemController).health()).resolves.toEqual({
        status: 'ready',
      });
      expect(
        Reflect.getMetadata('imports', AppModule).map(
          (entry: { name?: string }) => entry.name,
        ),
      ).not.toEqual(
        expect.arrayContaining([
          'GrpcModule',
          'RoutesModule',
          'MongooseModule',
        ]),
      );
    } finally {
      await module.close();
    }
  });
});
