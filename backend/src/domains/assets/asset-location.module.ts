import { Module, type OnModuleInit } from '@nestjs/common';
import { DatabaseModule } from '../../app/modules/database.module';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AuthModule } from '../auth/auth.module';
import { AssetLocationController } from './asset-location.controller';
import { AssetLocationRepository } from './asset-location.repository';

/** Optional location module remains separate from legacy asset schemas. */
@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [AssetLocationController],
  providers: [
    {
      provide: AssetLocationRepository,
      inject: [PostgresDatabase],
      useFactory: (database: PostgresDatabase) =>
        new AssetLocationRepository(database),
    },
  ],
})
export class AssetLocationModule implements OnModuleInit {
  constructor(private readonly repository: AssetLocationRepository) {}
  /** Check readiness without creating or modifying schema. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }
}
