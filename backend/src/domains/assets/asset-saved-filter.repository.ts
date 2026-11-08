import { randomUUID } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from '@nestjs/common';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { isAccountId } from '../auth/account.repository';
import {
  validateSavedFilterName,
  validateSavedFilterQuery,
} from './asset-saved-filter';

/** Persist query definitions only, with owner-scoped capacity serialization. */
export class AssetSavedFilterRepository {
  constructor(private readonly database: PostgresDatabase) {}

  private owner(value: string): string {
    if (!isAccountId(value)) throw new Error('invalid_saved_filter_owner');
    return value.toLowerCase();
  }

  /** Verify optional schema without applying migrations or reading records. */
  async ready(): Promise<void> {
    await this.database.pool.query(
      'SELECT id,owner_id,name,query_schema_version,query,version,created_at,updated_at FROM assets.saved_filters LIMIT 0',
    );
  }

  /** Return bounded owned definitions; malformed stored queries fail closed. */
  async list(owner: string) {
    const result = await this.database.pool.query(
      'SELECT id,name,query_schema_version AS "schemaVersion",query,version FROM assets.saved_filters WHERE owner_id=$1 ORDER BY name COLLATE "C",id LIMIT 21',
      [this.owner(owner)],
    );
    if (result.rows.length > 20)
      throw new Error('saved_filter_capacity_invariant');
    return result.rows.map((row) => {
      if (row.schemaVersion !== 1)
        throw new Error('unsupported_saved_filter_schema');
      return {
        ...row,
        name: validateSavedFilterName(row.name),
        query: validateSavedFilterQuery(row.query),
      };
    });
  }

  /** Insert once; account row locking serializes concurrent capacity checks. */
  async create(owner: string, name: unknown, query: unknown) {
    const account = this.owner(owner);
    const label = validateSavedFilterName(name);
    const definition = validateSavedFilterQuery(query);
    const client = await this.database.pool.connect();
    try {
      await client.query('BEGIN');
      const locked = await client.query(
        'SELECT id FROM auth.accounts WHERE id=$1 FOR UPDATE',
        [account],
      );
      if (locked.rows.length !== 1)
        throw new Error('saved_filter_owner_missing');
      const count = await client.query(
        'SELECT count(*)::integer AS total FROM assets.saved_filters WHERE owner_id=$1',
        [account],
      );
      if (!Number.isInteger(count.rows[0]?.total) || count.rows[0].total < 0)
        throw new Error('invalid_saved_filter_count');
      if (count.rows[0].total >= 20)
        throw new ConflictException('Saved filter limit reached');
      const result = await client.query(
        'INSERT INTO assets.saved_filters(id,owner_id,name,query_schema_version,query) VALUES($1,$2,$3,1,$4::jsonb) RETURNING id,name,query_schema_version AS "schemaVersion",query,version',
        [randomUUID(), account, label, JSON.stringify(definition)],
      );
      if (result.rows.length !== 1)
        throw new Error('saved_filter_write_invariant');
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* Preserve original failure; never retry an uncertain commit. */
      }
      throw error;
    } finally {
      client.release();
    }
  }
  /** Replace or delete an owned view against its locked current version. */
  async change(
    owner: string,
    id: string,
    version: number,
    replacement?: { name: unknown; query: unknown },
  ) {
    const account = this.owner(owner);
    if (
      !Number.isInteger(version) ||
      version < 1 ||
      version > (replacement ? 2147483646 : 2147483647)
    )
      throw new BadRequestException('Invalid saved filter version');
    const checked = replacement
      ? {
          name: validateSavedFilterName(replacement.name),
          query: validateSavedFilterQuery(replacement.query),
        }
      : undefined;
    const client = await this.database.pool.connect();
    try {
      await client.query('BEGIN');
      const current = await client.query(
        'SELECT version FROM assets.saved_filters WHERE owner_id=$1 AND id=$2 FOR UPDATE',
        [account, id],
      );
      if (current.rows.length !== 1)
        throw new NotFoundException('Saved filter is unavailable');
      if (current.rows[0].version !== version)
        throw new ConflictException(
          'Saved filter changed; reload before editing',
        );
      const result = checked
        ? await client.query(
            'UPDATE assets.saved_filters SET name=$3,query=$4::jsonb,version=version+1,updated_at=clock_timestamp() WHERE owner_id=$1 AND id=$2 RETURNING id,name,query_schema_version AS "schemaVersion",query,version',
            [account, id, checked.name, JSON.stringify(checked.query)],
          )
        : await client.query(
            'DELETE FROM assets.saved_filters WHERE owner_id=$1 AND id=$2 RETURNING id',
            [account, id],
          );
      if (result.rows.length !== 1)
        throw new Error('saved_filter_write_invariant');
      await client.query('COMMIT');
      return result.rows[0];
    } catch (error) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* Never retry an uncertain write. */
      }
      throw error;
    } finally {
      client.release();
    }
  }
}
