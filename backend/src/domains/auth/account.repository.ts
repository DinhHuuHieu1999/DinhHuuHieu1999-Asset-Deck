import type { roleAuthEnum } from '../../shared/enums/role-auth.enum';
import type { statusAuthEnum } from '../../shared/enums/status-auth.enum';

/** Validates stable legacy account identifiers independently of the selected database. */
export function isAccountId(value: string): boolean {
  return /^[0-9a-f]{24}$/i.test(value);
}

/** Persisted account state shared by authentication transports, without ORM behavior. */
export interface Account {
  id: string;
  email: string;
  username: string;
  name: string;
  passwordHash: string;
  role: roleAuthEnum;
  status: statusAuthEnum;
  passwordChangedAt?: Date;
  resetPasswordTokenHash?: string;
  resetPasswordExpiresAt?: Date;
  failedLoginAttempts: number;
  lockLevel: number;
  lockUntil?: Date;
  lastLoginAt?: Date;
  requireReverify: boolean;
  createdAt?: Date;
  updatedAt?: Date;
}

/** Validated domain query, translated separately by each storage adapter. */
export interface AccountFilter {
  status?: statusAuthEnum;
  role?: roleAuthEnum;
  search?: string;
  lastLoginSince?: Date;
  createdSince?: Date;
}

/** Storage boundary used by HTTP, JWT and gRPC account workflows. */
export abstract class AccountRepository {
  abstract findById(id: string): Promise<Account | null>;
  abstract findByIdentity(
    email: string,
    username: string,
  ): Promise<Account | null>;
  abstract findByEmail(email: string): Promise<Account | null>;
  abstract findByResetToken(hash: string, now: Date): Promise<Account | null>;
  abstract create(
    account: Pick<
      Account,
      'email' | 'username' | 'name' | 'passwordHash' | 'role' | 'status'
    >,
  ): Promise<Account>;
  abstract save(account: Account): Promise<void>;
  abstract find(
    filter: AccountFilter,
    options?: {
      sort?: 'name' | 'createdAt' | 'updatedAt';
      skip?: number;
      limit?: number;
    },
  ): Promise<Account[]>;
  abstract count(filter: AccountFilter): Promise<number>;
}
