import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetExportV4Controller } from './asset-export-v4.controller';
import { AssetExportV4Repository } from './asset-export-v4.repository';

/** Optional v4 export remains separate from existing asset schemas. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetExportV4Controller],
  providers: [
    {
      provide: AssetExportV4Repository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetExportV4Repository(database),
    },
  ],
})
export class AssetExportV4Module implements OnModuleInit {
  constructor(private readonly repository: AssetExportV4Repository) {}
  /** Check readiness without creating or modifying schema. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
