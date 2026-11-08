import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetCheckController } from './asset-check.controller';
import { AssetCheckRepository } from './asset-check.repository';

/** Enabled only by explicit startup configuration after migration 006. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetCheckController],
  providers: [
    {
      provide: AssetCheckRepository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetCheckRepository(database),
    },
  ],
})
export class AssetCheckModule implements OnModuleInit {
  constructor(private readonly repository: AssetCheckRepository) {}
  /** Fail closed if optional schema is missing. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
