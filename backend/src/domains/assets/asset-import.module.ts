// Adapted from the ToolDeck opt-in import source contract.
import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetImportController } from './asset-import.controller';
import { AssetImportRepository } from './asset-import.repository';

/** Separately opt-in write capability; never applies migrations. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetImportController],
  providers: [
    {
      provide: AssetImportRepository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetImportRepository(database),
    },
  ],
})
export class AssetImportModule implements OnModuleInit {
  constructor(private readonly repository: AssetImportRepository) {}

  /** Refuse startup if the separately migrated schema cannot be accessed. */
  async onModuleInit(): Promise<void> {
    await this.repository.assertReady();
  }
}
