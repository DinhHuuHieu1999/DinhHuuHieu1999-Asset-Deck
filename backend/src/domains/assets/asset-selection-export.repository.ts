import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { isAccountId } from '../auth/account.repository';
import { ASSET_EXPORT_MAX_RECORDS } from './asset-export';
import type { AssetExportV3Snapshot } from './asset-export-v3';
import {
  validateAssetSelectionScope,
  type AssetSelectionScope,
} from './asset-selection-export';
import { assetOrderBy } from './asset-sort';

/** Read a filtered selection without changing full inventory export contracts. */
export class AssetSelectionExportRepository {
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
  async exportSnapshot(
    owner: string,
    input: AssetSelectionScope,
  ): Promise<AssetExportV3Snapshot> {
    const scope = validateAssetSelectionScope(input);
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
          AND ($3='' OR strpos(lower(name),lower($3))>0
            OR strpos(lower(category),lower($3))>0 OR strpos(lower(serial),lower($3))>0)
          AND ($4='' OR status=$4) AND ($5='' OR category=$5)
          AND ($6='all' OR ($6='unknown' AND location IS NULL)
            OR ($6='exact' AND location=$7))
          AND ($8='' OR ($8='expired' AND warranty_expires_on < $9::date)
            OR ($8='expiring_soon' AND warranty_expires_on >= $9::date
              AND warranty_expires_on <= $10::date))
          ORDER BY ${assetOrderBy(scope.sort)} LIMIT $2
        ) record), '[]'::json) AS records`,
      [
        this.owner(owner),
        ASSET_EXPORT_MAX_RECORDS + 1,
        scope.q,
        scope.status,
        scope.category,
        scope.locationMode,
        scope.location,
        scope.warranty?.filter ?? '',
        scope.warranty?.asOf ?? null,
        scope.warranty?.through ?? null,
      ],
    );
    if (!result.rows[0]) throw new Error('asset_snapshot_missing');
    return result.rows[0];
  }
}
