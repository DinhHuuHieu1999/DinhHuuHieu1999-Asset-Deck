import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { isAccountId } from '../auth/account.repository';
import type { AssetDatesUpdate } from './asset-dates';

export interface AssetDatesRecord {
  id: string;
  version: number;
  purchasedOn: string | null;
  warrantyExpiresOn: string | null;
}
const projection = `id, version,
  to_char(purchased_on, 'YYYY-MM-DD') AS "purchasedOn",
  to_char(warranty_expires_on, 'YYYY-MM-DD') AS "warrantyExpiresOn"`;

/** Separate owner-scoped date persistence; shares the asset optimistic version. */
export class AssetDatesRepository {
  constructor(private readonly database: PostgresDatabase) {}

  private owner(value: string): string {
    if (!isAccountId(value)) throw new Error('invalid_asset_owner');
    return value.toLowerCase();
  }

  /** Require explicit migration 004 without applying schema changes. */
  async ready(): Promise<void> {
    await this.database.pool.query(
      `SELECT ${projection}, owner_id FROM assets.assets LIMIT 0`,
    );
  }

  /** Missing and non-owned records both return null without exposing existence. */
  async read(owner: string, id: string): Promise<AssetDatesRecord | null> {
    const result = await this.database.pool.query<AssetDatesRecord>(
      `SELECT ${projection} FROM assets.assets WHERE owner_id=$1 AND id=$2`,
      [this.owner(owner), id],
    );
    return result.rows[0] ?? null;
  }

  /** Only dates/version/timestamp change; existing asset fields remain intact. */
  async update(
    owner: string,
    id: string,
    input: Readonly<AssetDatesUpdate>,
  ): Promise<AssetDatesRecord | null> {
    const result = await this.database.pool.query<AssetDatesRecord>(
      `UPDATE assets.assets SET purchased_on=$4::date,warranty_expires_on=$5::date,
       version=version+1,updated_at=clock_timestamp()
       WHERE owner_id=$1 AND id=$2 AND version=$3 RETURNING ${projection}`,
      [
        this.owner(owner),
        id,
        input.version,
        input.purchasedOn,
        input.warrantyExpiresOn,
      ],
    );
    return result.rows[0] ?? null;
  }
}
