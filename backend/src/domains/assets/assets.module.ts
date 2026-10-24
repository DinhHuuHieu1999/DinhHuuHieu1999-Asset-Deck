import { Module } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetsController } from './assets.controller';
import { AssetsRepository } from './assets.repository';
import { AssetsService } from './assets.service';

/** Product-owned assets with explicit account and database dependencies. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetsController],
  providers: [
    AssetsService,
    {
      provide: AssetsRepository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetsRepository(database),
    },
  ],
})
export class AssetsModule {}
