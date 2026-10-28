import { assetOrderBy } from './asset-sort';
import {
  buildAssetWarrantyOverview,
  type AssetWarrantyOverviewRow,
} from './asset-warranty-overview';
import { UnprocessableEntityException } from '@nestjs/common';
import type { AssetWarrantyQueryDto } from './asset-warranty.dto';
import type { AssetWarrantyWindow } from './asset-warranty';
import type { AssetExportV2Record } from './asset-export-v2';
import { ASSET_EXPORT_MAX_RECORDS } from './asset-export';
import type { AssetExportV2Snapshot } from './asset-export-v2';
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

  /** One statement snapshot counts all owned assets; no list or category limits. */
  async warrantyOverview(owner: string, window: Readonly<AssetWarrantyWindow>) {
    const result = await this.database.pool.query<AssetWarrantyOverviewRow>(
      `SELECT count(*)::text AS total,
        (count(*) FILTER (WHERE warranty_expires_on < $2::date))::text AS expired,
        (count(*) FILTER (WHERE warranty_expires_on >= $2::date
          AND warranty_expires_on <= $3::date))::text AS "expiringSoon",
        (count(*) FILTER (WHERE warranty_expires_on > $3::date))::text AS later,
        (count(*) FILTER (WHERE warranty_expires_on IS NULL))::text AS unknown
       FROM assets.assets WHERE owner_id=$1`,
      [this.owner(owner), window.asOf, window.through],
    );
    if (result.rows.length !== 1 || !result.rows[0]) {
      throw new Error('asset_warranty_overview_missing_aggregate');
    }
    return buildAssetWarrantyOverview(result.rows[0], window);
  }

  /** Apply all predicates before a bounded page; NULL warranty never matches. */
  async warrantyList(
    owner: string,
    query: AssetWarrantyQueryDto,
    window: Readonly<AssetWarrantyWindow>,
  ) {
    const result = await this.database.pool.query<AssetExportV2Record>(
      `SELECT id,name,category,serial,status,notes,version,
        to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
        to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt",
        to_char(purchased_on, 'YYYY-MM-DD') AS "purchasedOn",
        to_char(warranty_expires_on, 'YYYY-MM-DD') AS "warrantyExpiresOn"
       FROM assets.assets WHERE owner_id=$1
       AND ($3='' OR strpos(lower(name),lower($3))>0
         OR strpos(lower(category),lower($3))>0 OR strpos(lower(serial),lower($3))>0)
       AND ($4='' OR status=$4) AND ($5='' OR category=$5)
       AND (($6='expired' AND warranty_expires_on < $7::date)
         OR ($6='expiring_soon' AND warranty_expires_on >= $7::date
           AND warranty_expires_on <= $8::date))
       ORDER BY ${assetOrderBy(query.sort)} LIMIT 51 OFFSET $2`,
      [
        this.owner(owner),
        query.offset,
        query.q.trim(),
        query.status,
        (query.category ?? '').trim(),
        window.filter,
        window.asOf,
        window.through,
      ],
    );
    const nextOffset = result.rows.length > 50 ? query.offset + 50 : null;
    if (nextOffset !== null && nextOffset > 100000) {
      throw new UnprocessableEntityException(
        'Pagination limit reached; list is incomplete',
      );
    }
    return {
      items: result.rows.slice(0, 50),
      nextOffset,
      warranty: window.filter,
      asOf: window.asOf,
      through: window.through,
    };
  }

  /** Read all public fields and dates from one owner-scoped statement snapshot. */
  async exportSnapshot(owner: string): Promise<AssetExportV2Snapshot> {
    const result = await this.database.pool.query<AssetExportV2Snapshot>(
      `SELECT to_char(statement_timestamp() AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "exportedAt",
        COALESCE((SELECT json_agg(record) FROM (
          SELECT id,name,category,serial,status,notes,version,
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
