import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { isAccountId } from '../auth/account.repository';
import { ASSET_EXPORT_MAX_RECORDS } from './asset-export';
import type { AssetExportV3Snapshot } from './asset-export-v3';

/** Separate v3 snapshot access leaves existing export repositories unchanged. */
export class AssetExportV3Repository {
  constructor(private readonly database: PostgresDatabase) {}

  private owner(owner: string): string {
    if (!isAccountId(owner)) throw new Error('invalid_asset_owner');
    return owner.toLowerCase();
  }

  /** Refuse missing date/location schema without applying migrations. */
  async ready(): Promise<void> {
    await this.database.pool.query(
      'SELECT id,owner_id,location,purchased_on,warranty_expires_on FROM assets.assets LIMIT 0',
    );
  }

  /** Read all public fields, dates and location from one owner-scoped statement snapshot. */
  async exportSnapshot(owner: string): Promise<AssetExportV3Snapshot> {
    const result = await this.database.pool.query<AssetExportV3Snapshot>(
      `SELECT to_char(statement_timestamp() AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "exportedAt",
        COALESCE((SELECT json_agg(record) FROM (
          SELECT id,name,category,serial,status,notes,version,location,
            to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
            to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt",
            to_char(purchased_on, 'YYYY-MM-DD') AS "purchasedOn",
            to_char(warranty_expires_on, 'YYYY-MM-DD') AS "warrantyExpiresOn"
          FROM assets.assets WHERE owner_id=$1
          ORDER BY updated_at DESC,id DESC LIMIT $2
        ) record), '[]'::json) AS records`,
      [this.owner(owner), ASSET_EXPORT_MAX_RECORDS + 1],
    );
    if (!result.rows[0]) throw new Error('asset_snapshot_missing');
    return result.rows[0];
  }
}
