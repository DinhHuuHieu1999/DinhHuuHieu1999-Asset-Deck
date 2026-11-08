import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetExportV3Controller } from './asset-export-v3.controller';
import { AssetExportV3Repository } from './asset-export-v3.repository';

/** Optional v3 export remains separate from existing asset schemas. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetExportV3Controller],
  providers: [
    {
      provide: AssetExportV3Repository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetExportV3Repository(database),
    },
  ],
})
export class AssetExportV3Module implements OnModuleInit {
  constructor(private readonly repository: AssetExportV3Repository) {}
  /** Check readiness without creating or modifying schema. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
