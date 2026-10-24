import { Global, Module } from '@nestjs/common';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';

/** PostgreSQL-only storage; startup checks schema but never migrates it. */
@Global()
@Module({ providers: [PostgresDatabase], exports: [PostgresDatabase] })
export class DatabaseModule {}
