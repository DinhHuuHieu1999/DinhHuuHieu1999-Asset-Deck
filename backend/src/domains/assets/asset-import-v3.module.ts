// Adapted from the ToolDeck opt-in import source contract.
import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetImportV3Controller } from './asset-import-v3.controller';
import { AssetImportV3Repository } from './asset-import-v3.repository';

/** Separately opt-in write capability; never applies migrations. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetImportV3Controller],
  providers: [
    {
      provide: AssetImportV3Repository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetImportV3Repository(database),
    },
  ],
})
export class AssetImportV3Module implements OnModuleInit {
  constructor(private readonly repository: AssetImportV3Repository) {}

  /** Refuse startup if the separately migrated schema cannot be accessed. */
  async onModuleInit(): Promise<void> {
    await this.repository.assertReady();
  }
}
