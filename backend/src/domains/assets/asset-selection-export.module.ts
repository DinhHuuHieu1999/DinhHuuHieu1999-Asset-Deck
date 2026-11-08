import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetSelectionExportController } from './asset-selection-export.controller';
import { AssetSelectionExportRepository } from './asset-selection-export.repository';

/** Optional filtered export requires explicit date/location readiness. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetSelectionExportController],
  providers: [
    {
      provide: AssetSelectionExportRepository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetSelectionExportRepository(database),
    },
  ],
})
export class AssetSelectionExportModule implements OnModuleInit {
  constructor(private readonly repository: AssetSelectionExportRepository) {}
  /** Check readiness without creating or modifying schema. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
