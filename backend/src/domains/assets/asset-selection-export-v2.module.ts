import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetSelectionExportV2Controller } from './asset-selection-export-v2.controller';
import { AssetSelectionExportV2Repository } from './asset-selection-export-v2.repository';

/** Optional filtered export requires explicit date/location readiness. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetSelectionExportV2Controller],
  providers: [
    {
      provide: AssetSelectionExportV2Repository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetSelectionExportV2Repository(database),
    },
  ],
})
export class AssetSelectionExportV2Module implements OnModuleInit {
  constructor(private readonly repository: AssetSelectionExportV2Repository) {}
  /** Check readiness without creating or modifying schema. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
