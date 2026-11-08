// Adapted from the ToolDeck opt-in import source contract.
import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetImportV2Controller } from './asset-import-v2.controller';
import { AssetImportV2Repository } from './asset-import-v2.repository';

/** Separately opt-in write capability; never applies migrations. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetImportV2Controller],
  providers: [
    {
      provide: AssetImportV2Repository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetImportV2Repository(database),
    },
  ],
})
export class AssetImportV2Module implements OnModuleInit {
  constructor(private readonly repository: AssetImportV2Repository) {}

  /** Refuse startup if the separately migrated schema cannot be accessed. */
  async onModuleInit(): Promise<void> {
    await this.repository.assertReady();
  }
}
