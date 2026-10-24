import { Module, RequestMethod, type MiddlewareConsumer } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { CacheModule } from '@nestjs/cache-manager';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { getEnvFilePaths } from '../config/env-files';
import { readNumber } from '../config/runtime.config';
import { CsrfModule } from './csrf.module';
import { DatabaseModule } from './database.module';
import { CsrfMiddleware } from '../middleware/csrf.middleware';
import { AuthModule } from '../../domains/auth/auth.module';
import { AssetsModule } from '../../domains/assets/assets.module';
import { IpWhitelistGuard } from '../../infrastructure/guards/ip-whitelist.guard';
import { RequestFreshnessGuard } from '../../infrastructure/guards/request-freshness.guard';
import { SystemController } from '../system.controller';

/** Asset Desk composition without ToolDeck domains, MongoDB, workers or gRPC. */
@Module({
  imports: [
    ConfigModule.forRoot({ envFilePath: getEnvFilePaths(), isGlobal: true }),
    CacheModule.register({ isGlobal: true, ttl: 15000, max: 1000 }),
    ThrottlerModule.forRoot([
      {
        ttl: readNumber('THROTTLE_TTL_MS', 60000),
        limit: readNumber('THROTTLE_LIMIT', 60),
      },
    ]),
    DatabaseModule,
    CsrfModule,
    AuthModule,
    AssetsModule,
  ],
  controllers: [SystemController],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: IpWhitelistGuard },
    { provide: APP_GUARD, useClass: RequestFreshnessGuard },
  ],
})
export class AppModule {
  /** Protect every state-changing route, including authentication endpoints. */
  configure(consumer: MiddlewareConsumer): void {
    consumer
      .apply(CsrfMiddleware)
      .forRoutes(
        ...[
          RequestMethod.POST,
          RequestMethod.PUT,
          RequestMethod.PATCH,
          RequestMethod.DELETE,
        ].map((method) => ({ path: '{*path}', method })),
      );
  }
}
