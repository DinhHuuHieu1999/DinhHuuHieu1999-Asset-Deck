import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetSavedFilterController } from './asset-saved-filter.controller';
import { AssetSavedFilterRepository } from './asset-saved-filter.repository';

/** Optional owner-scoped definitions, separate from inventory writes. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetSavedFilterController],
  providers: [
    {
      provide: AssetSavedFilterRepository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetSavedFilterRepository(database),
    },
  ],
})
export class AssetSavedFilterModule implements OnModuleInit {
  constructor(private readonly repository: AssetSavedFilterRepository) {}
  /** Missing optional schema refuses startup; never migrate automatically. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
