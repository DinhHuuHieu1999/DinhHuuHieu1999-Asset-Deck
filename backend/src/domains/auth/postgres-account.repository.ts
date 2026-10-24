import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import {
  AccountRepository,
  isAccountId,
  type Account,
  type AccountFilter,
} from './account.repository';

const columns = {
  id: 'id',
  email: 'email',
  username: 'username',
  name: 'name',
  passwordHash: 'password_hash',
  role: 'role',
  status: 'status',
  passwordChangedAt: 'password_changed_at',
  resetPasswordTokenHash: 'reset_password_token_hash',
  resetPasswordExpiresAt: 'reset_password_expires_at',
  failedLoginAttempts: 'failed_login_attempts',
  lockLevel: 'lock_level',
  lockUntil: 'lock_until',
  lastLoginAt: 'last_login_at',
  requireReverify: 'require_reverify',
  createdAt: 'created_at',
  updatedAt: 'updated_at',
} as const satisfies Record<keyof Account, string>;
const projection = Object.entries(columns)
  .map(([key, column]) => `${column} AS "${key}"`)
  .join(', ');
const mutableFields = [
  'passwordHash',
  'status',
  'passwordChangedAt',
  'resetPasswordTokenHash',
  'resetPasswordExpiresAt',
  'failedLoginAttempts',
  'lockLevel',
  'lockUntil',
  'lastLoginAt',
  'requireReverify',
] as const;

/** Parameterized SQL implementation of the shared account boundary. */
@Injectable()
export class PostgresAccountRepository extends AccountRepository {
  private readonly snapshots = new WeakMap<Account, Account>();

  constructor(private readonly database: PostgresDatabase) {
    super();
  }

  private snapshot(account: Account): Account {
    const copy = { ...account };
    for (const [key, value] of Object.entries(account)) {
      if (value instanceof Date)
        Reflect.set(copy, key, new Date(value.getTime()));
    }
    return copy;
  }

  private map(row: Account): Account {
    const account = { ...row };
    for (const key of Object.keys(columns)) {
      if (Reflect.get(account, key) === null)
        Reflect.set(account, key, undefined);
    }
    this.snapshots.set(account, this.snapshot(account));
    return account;
  }

  private async one(where: string, values: unknown[]): Promise<Account | null> {
    // `where` is built only from fixed SQL in this adapter; request values are bound separately.
    const result = await this.database.pool.query<Account>(
      `SELECT ${projection} FROM auth.accounts WHERE ${where} LIMIT 1`,
      values,
    );
    const row = result.rows[0];
    return row ? this.map(row) : null;
  }

  /** Retains legacy account ID compatibility across HTTP and gRPC. */
  async findById(id: string): Promise<Account | null> {
    if (!isAccountId(id)) return null;
    return this.one('id = $1', [id.toLowerCase()]);
  }

  /** Looks up normalized account identity using parameters, not interpolated values. */
  async findByIdentity(
    email: string,
    username: string,
  ): Promise<Account | null> {
    return this.one('email = $1 OR username = $2', [email, username]);
  }

  /** Looks up a normalized email. */
  async findByEmail(email: string): Promise<Account | null> {
    return this.one('email = $1', [email]);
  }

  /** Requires reset credentials to be unexpired at lookup time. */
  async findByResetToken(hash: string, now: Date): Promise<Account | null> {
    return this.one(
      'reset_password_token_hash = $1 AND reset_password_expires_at > $2',
      [hash, now],
    );
  }

  /** Creates one account, preserving the existing 24-hex identifier contract. */
  async create(
    account: Parameters<AccountRepository['create']>[0],
  ): Promise<Account> {
    try {
      const result = await this.database.pool.query<Account>(
        `INSERT INTO auth.accounts (id, email, username, name, password_hash, role, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING ${projection}`,
        [
          randomBytes(12).toString('hex'),
          account.email,
          account.username,
          account.name,
          account.passwordHash,
          account.role,
          account.status,
        ],
      );
      const row = result.rows[0];
      if (!row) throw new Error('Account creation returned no record');
      return this.map(row);
    } catch (error: unknown) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === '23505' &&
        'constraint' in error
      ) {
        if (error.constraint === 'accounts_email_key')
          throw new BadRequestException('Email already exists');
        if (error.constraint === 'accounts_username_key')
          throw new BadRequestException('Username already exists');
      }
      throw error;
    }
  }

  /** Writes changed auth fields only; explicitly cleared state becomes SQL NULL. */
  async save(account: Account): Promise<void> {
    const snapshot = this.snapshots.get(account);
    if (!snapshot)
      throw new Error(
        'Account must be loaded by this repository before saving',
      );
    const values: unknown[] = [];
    const assignments: string[] = [];
    for (const key of mutableFields) {
      const before = snapshot[key];
      const after = account[key];
      if (
        before === after ||
        (before instanceof Date &&
          after instanceof Date &&
          before.getTime() === after.getTime())
      )
        continue;
      values.push(after ?? null);
      assignments.push(`${columns[key]} = $${values.length}`);
    }
    if (!assignments.length) return;
    const updatedAt = new Date();
    values.push(updatedAt);
    assignments.push(`updated_at = $${values.length}`);
    values.push(account.id);
    const result = await this.database.pool.query(
      `UPDATE auth.accounts SET ${assignments.join(', ')} WHERE id = $${values.length}`,
      values,
    );
    if (result.rowCount !== 1) throw new NotFoundException('User not found');
    account.updatedAt = updatedAt;
    this.snapshots.set(account, this.snapshot(account));
  }

  private filter(input: AccountFilter): { where: string; values: unknown[] } {
    const values: unknown[] = [];
    const conditions: string[] = [];
    const add = (column: string, operator: string, value: unknown): void => {
      values.push(value);
      conditions.push(`${column} ${operator} $${values.length}`);
    };
    if (input.status) add('status', '=', input.status);
    if (input.role) add('role', '=', input.role);
    if (input.lastLoginSince) add('last_login_at', '>=', input.lastLoginSince);
    if (input.createdSince) add('created_at', '>=', input.createdSince);
    if (input.search?.trim()) {
      values.push(input.search.trim());
      const parameter = `$${values.length}`;
      conditions.push(
        `(strpos(lower(email), lower(${parameter})) > 0 OR strpos(lower(username), lower(${parameter})) > 0 OR strpos(lower(name), lower(${parameter})) > 0)`,
      );
    }
    return {
      where: conditions.length ? `WHERE ${conditions.join(' AND ')}` : '',
      values,
    };
  }

  /** Lists snapshots with allowlisted sorting and parameterized paging/search. */
  async find(
    filter: AccountFilter,
    options: NonNullable<Parameters<AccountRepository['find']>[1]> = {},
  ): Promise<Account[]> {
    const { where, values } = this.filter(filter);
    const sort = options.sort ?? 'createdAt';
    if (!['name', 'createdAt', 'updatedAt'].includes(sort))
      throw new Error('Invalid account sort');
    let paging = '';
    if (options.limit !== undefined) {
      if (!Number.isInteger(options.limit) || options.limit <= 0)
        throw new Error('Invalid account limit');
      values.push(options.limit);
      paging += ` LIMIT $${values.length}`;
    }
    if (options.skip !== undefined) {
      if (!Number.isInteger(options.skip) || options.skip < 0)
        throw new Error('Invalid account offset');
      values.push(options.skip);
      paging += ` OFFSET $${values.length}`;
    }
    const result = await this.database.pool.query<Account>(
      `SELECT ${projection} FROM auth.accounts ${where} ORDER BY ${columns[sort]} ${sort === 'name' ? 'ASC' : 'DESC'}${paging}`,
      values,
    );
    return result.rows.map((row) => this.map(row));
  }

  /** Counts using the same account filters as list queries. */
  async count(filter: AccountFilter): Promise<number> {
    const { where, values } = this.filter(filter);
    const result = await this.database.pool.query<{ total: string }>(
      `SELECT count(*) AS total FROM auth.accounts ${where}`,
      values,
    );
    const count = Number(result.rows[0]?.total);
    if (!Number.isSafeInteger(count) || count < 0)
      throw new Error('Invalid account count');
    return count;
  }
}
