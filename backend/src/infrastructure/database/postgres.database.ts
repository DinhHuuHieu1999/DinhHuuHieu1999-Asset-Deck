import {
  Injectable,
  Logger,
  type OnModuleDestroy,
  type OnModuleInit,
} from '@nestjs/common';
import { Pool } from 'pg';

/** App-owned PostgreSQL connection pool; never creates or migrates schemas on startup. */
@Injectable()
export class PostgresDatabase implements OnModuleInit, OnModuleDestroy {
  readonly pool: Pool;
  private readonly logger = new Logger(PostgresDatabase.name);
  private readonly shutdownTasks: Array<() => Promise<void>> = [];

  constructor() {
    const connectionString = process.env.AUTH_POSTGRES_URL?.trim();
    if (!connectionString)
      throw new Error('AUTH_POSTGRES_URL is required for postgres accounts');
    try {
      const url = new URL(connectionString);
      if (
        !['postgres:', 'postgresql:'].includes(url.protocol) ||
        !url.hostname ||
        url.pathname.length <= 1
      )
        throw new Error('Invalid URL');
    } catch {
      throw new Error(
        'AUTH_POSTGRES_URL must be a PostgreSQL URL with an explicit host and database',
      );
    }
    const integer = (name: string, fallback: number): number => {
      const raw = Reflect.get(process.env, name);
      if (raw === undefined) return fallback;
      const value = Number(raw);
      if (!Number.isInteger(value) || value <= 0)
        throw new Error(`${name} must be a positive integer`);
      return value;
    };
    this.pool = new Pool({
      connectionString,
      max: integer('AUTH_POSTGRES_POOL_SIZE', 10),
      connectionTimeoutMillis: integer(
        'AUTH_POSTGRES_CONNECT_TIMEOUT_MS',
        5_000,
      ),
      idleTimeoutMillis: 30_000,
      statement_timeout: integer('AUTH_POSTGRES_STATEMENT_TIMEOUT_MS', 5_000),
      application_name: 'asset-desk-auth',
    });
    this.pool.on('error', () => {
      // Connection errors may contain host/user details; do not log connection strings.
      this.logger.error(
        'PostgreSQL idle connection failed; the pool will reconnect on demand',
      );
    });
  }

  /** Fails startup if the operator has not applied the explicit account migration. */
  async onModuleInit(): Promise<void> {
    await this.pool
      .query(`SELECT id, email, username, name, password_hash, role, status,
      password_changed_at, reset_password_token_hash, reset_password_expires_at,
      failed_login_attempts, lock_level, lock_until, last_login_at, require_reverify,
      created_at, updated_at FROM auth.accounts LIMIT 0`);
  }

  /** Releases connections during application shutdown. */
  async onModuleDestroy(): Promise<void> {
    for (const task of this.shutdownTasks) await task();
    await this.pool.end();
  }

  /** Register owned background work that must drain before this pool closes. */
  beforePoolClose(task: () => Promise<void>): void {
    this.shutdownTasks.push(task);
  }

  /** Verifies the selected account schema is reachable without reading private records. */
  async isReady(): Promise<boolean> {
    try {
      await this.pool.query('SELECT id FROM auth.accounts LIMIT 0');
      return true;
    } catch {
      return false;
    }
  }
}
