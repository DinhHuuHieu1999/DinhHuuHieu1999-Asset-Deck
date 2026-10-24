import { Module } from '@nestjs/common';
import { PassportModule } from '@nestjs/passport';
import { DatabaseModule } from '../../app/modules/database.module';
import { LocalStrategy } from '../../infrastructure/strategies/local.strategy';
import { JwtStrategy } from '../../infrastructure/strategies/jwt.strategy';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { AccountRepository } from './account.repository';
import { PostgresAccountRepository } from './postgres-account.repository';

/** Reuses account security with one explicit PostgreSQL adapter. */
@Module({
  imports: [
    DatabaseModule,
    PassportModule.register({ defaultStrategy: 'jwt' }),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    LocalStrategy,
    JwtStrategy,
    { provide: AccountRepository, useClass: PostgresAccountRepository },
  ],
  exports: [AuthService, AccountRepository, PassportModule],
})
export class AuthModule {}
