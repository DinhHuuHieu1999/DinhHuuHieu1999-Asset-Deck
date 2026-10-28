import {
  buildAssetLocationOverview,
  type AssetLocationOverviewRow,
} from './asset-location-overview';
import type { AssetWarrantyWindow } from './asset-warranty';
import { UnprocessableEntityException } from '@nestjs/common';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { isAccountId } from '../auth/account.repository';
import type { AssetRecord } from './assets.repository';
import type { AssetQueryDto } from './assets.dto';
import {
  normalizeAssetLocation,
  type AssetLocationUpdate,
} from './asset-location';

export interface AssetLocationRecord {
  id: string;
  version: number;
  location: string | null;
}
export interface AssetLocationFilter {
  mode: 'all' | 'unknown' | 'exact';
  location: string | null;
}

/** Optional location persistence uses the existing owner and asset edit version. */
export class AssetLocationRepository {
  constructor(private readonly database: PostgresDatabase) {}

  private owner(owner: string): string {
    if (!isAccountId(owner)) throw new Error('invalid_asset_owner');
    return owner.toLowerCase();
  }

  /** Refuse enabled startup without explicit migration 005. */
  async ready(): Promise<void> {
    await this.database.pool.query(
      'SELECT id,owner_id,version,location FROM assets.assets LIMIT 0',
    );
  }

  /** Aggregate all owner assets in one snapshot; lookahead refuses partial groups. */
  async overview(owner: string) {
    const result = await this.database.pool.query<AssetLocationOverviewRow>(
      `SELECT location,count(*)::text AS count FROM assets.assets
       WHERE owner_id=$1 GROUP BY location
       ORDER BY location COLLATE "C" ASC NULLS FIRST LIMIT 1002`,
      [this.owner(owner)],
    );
    return buildAssetLocationOverview(result.rows);
  }

  /** Unknown and non-owned IDs have the same absent result. */
  async read(owner: string, id: string): Promise<AssetLocationRecord | null> {
    const result = await this.database.pool.query<AssetLocationRecord>(
      'SELECT id,version,location FROM assets.assets WHERE owner_id=$1 AND id=$2',
      [this.owner(owner), id],
    );
    return result.rows[0] ?? null;
  }

  /** Replace only location, version and timestamp under one optimistic predicate. */
  async update(
    owner: string,
    id: string,
    input: Readonly<AssetLocationUpdate>,
  ): Promise<AssetLocationRecord | null> {
    const result = await this.database.pool.query<AssetLocationRecord>(
      `UPDATE assets.assets SET location=$4,version=version+1,updated_at=clock_timestamp()
       WHERE owner_id=$1 AND id=$2 AND version=$3 RETURNING id,version,location`,
      [
        this.owner(owner),
        id,
        input.version,
        normalizeAssetLocation(input.location),
      ],
    );
    return result.rows[0] ?? null;
  }

  /** Combine literal filters before paging without changing legacy list/export schemas. */
  async list(
    owner: string,
    query: AssetQueryDto,
    filter: Readonly<AssetLocationFilter>,
    window?: Readonly<AssetWarrantyWindow>,
  ) {
    const result = await this.database.pool.query<
      AssetRecord & { location: string | null }
    >(
      `SELECT id,name,category,serial,status,notes,version,location,
       ${
         window
           ? `to_char(purchased_on, 'YYYY-MM-DD') AS "purchasedOn",
       to_char(warranty_expires_on, 'YYYY-MM-DD') AS "warrantyExpiresOn",`
           : ''
       }
       to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
       to_char(updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt"
       FROM assets.assets WHERE owner_id=$1
       AND ($3='' OR strpos(lower(name),lower($3))>0
         OR strpos(lower(category),lower($3))>0 OR strpos(lower(serial),lower($3))>0)
       AND ($4='' OR status=$4) AND ($5='' OR category=$5)
       AND ($6='all' OR ($6='unknown' AND location IS NULL)
         OR ($6='exact' AND location=$7))
       ${
         window
           ? `AND (($8='expired' AND warranty_expires_on < $9::date)
         OR ($8='expiring_soon' AND warranty_expires_on >= $9::date AND warranty_expires_on <= $10::date))`
           : ''
       }
       ORDER BY updated_at DESC,id DESC LIMIT 51 OFFSET $2`,
      [
        this.owner(owner),
        query.offset,
        query.q.trim(),
        query.status,
        (query.category ?? '').trim(),
        filter.mode,
        filter.location,
        ...(window ? [window.filter, window.asOf, window.through] : []),
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
      ...(window
        ? {
            warranty: window.filter,
            asOf: window.asOf,
            through: window.through,
          }
        : {}),
    };
  }
}
