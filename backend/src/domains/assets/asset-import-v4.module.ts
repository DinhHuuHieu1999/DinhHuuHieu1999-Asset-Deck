// Adapted from the ToolDeck opt-in import source contract.
import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetImportV4Controller } from './asset-import-v4.controller';
import { AssetImportV4Repository } from './asset-import-v4.repository';

/** Separately opt-in write capability; never applies migrations. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetImportV4Controller],
  providers: [
    {
      provide: AssetImportV4Repository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetImportV4Repository(database),
    },
  ],
})
export class AssetImportV4Module implements OnModuleInit {
  constructor(private readonly repository: AssetImportV4Repository) {}

  /** Refuse startup if the separately migrated schema cannot be accessed. */
  async onModuleInit(): Promise<void> {
    await this.repository.assertReady();
  }
}
