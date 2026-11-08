import { AssetWarrantyController } from './asset-warranty.controller';
import { AssetExportV2Controller } from './asset-export-v2.controller';
import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetDatesController } from './asset-dates.controller';
import { AssetDatesRepository } from './asset-dates.repository';

/** Explicitly enabled date capability; existing asset module remains independent. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [
    AssetDatesController,
    AssetExportV2Controller,
    AssetWarrantyController,
  ],
  providers: [
    {
      provide: AssetDatesRepository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetDatesRepository(database),
    },
  ],
})
export class AssetDatesModule implements OnModuleInit {
  constructor(private readonly repository: AssetDatesRepository) {}
  /** Refuse startup if the date schema is unavailable; never apply migration here. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
