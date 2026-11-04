import { assetCheckPredicate } from './asset-check';
import { assetOrderBy } from './asset-sort';
import {
  ASSET_OVERVIEW_MAX_CATEGORIES,
  buildAssetOverview,
  type AssetOverviewRow,
} from './asset-overview';
import { randomUUID } from 'node:crypto';
import { ASSET_EXPORT_MAX_RECORDS, type AssetSnapshot } from './asset-export';
import { isAccountId } from '../auth/account.repository';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import type { AssetInputDto, AssetQueryDto } from './assets.dto';

export interface AssetRecord extends AssetInputDto {
  id: string;
  version: number;
  createdAt: string;
  updatedAt: string;
}
const projection = `id, name, category, serial, status, notes, version,
  to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "createdAt",
  to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "updatedAt"`;

/** Parameterized owner-scoped persistence; never applies schema changes. */
export class AssetsRepository {
  constructor(private readonly database: PostgresDatabase) {}

  private owner(value: string): void {
    if (!isAccountId(value)) throw new Error('invalid_asset_owner');
  }

  /** Fail startup if the explicit asset migration has not been applied. */
  async ready(): Promise<void> {
    await this.database.pool.query(
      `SELECT ${projection}, owner_id FROM assets.assets LIMIT 0`,
    );
  }

  /** Search/filter the authenticated owner's rows before fixed-size pagination. */
  async list(owner: string, query: AssetQueryDto) {
    this.owner(owner);
    const result = await this.database.pool.query<AssetRecord>(
      `SELECT ${projection} FROM assets.assets WHERE owner_id=$1
       AND ($3='' OR strpos(lower(name),lower($3))>0
         OR strpos(lower(category),lower($3))>0 OR strpos(lower(serial),lower($3))>0)
       AND ($4='' OR status=$4)
       AND ($5='' OR category=$5)
       ${assetCheckPredicate(query.checkMode)}
       ORDER BY ${assetOrderBy(query.sort)} LIMIT 51 OFFSET $2`,
      [
        owner.toLowerCase(),
        query.offset,
        query.q.trim(),
        query.status,
        (query.category ?? '').trim(),
      ],
    );
    return {
      items: result.rows.slice(0, 50),
      nextOffset: result.rows.length > 50 ? query.offset + 50 : null,
    };
  }

  /** Read one owned asset without revealing whether another owner's ID exists. */
  public async findOne(owner: string, id: string): Promise<AssetRecord | null> {
    this.owner(owner);
    const result = await this.database.pool.query<AssetRecord>(
      `SELECT ${projection} FROM assets.assets WHERE owner_id=$1 AND id=$2::uuid`,
      [owner.toLowerCase(), id],
    );
    return result.rows[0] ?? null;
  }

  /** Check all owned rows using literal case-sensitive equality, without returning records. */
  public async serialDuplicate(
    owner: string,
    serial: string,
    excludeId?: string,
  ): Promise<{ duplicate: boolean }> {
    this.owner(owner);
    const result = await this.database.pool.query<{ duplicate: boolean }>(
      `SELECT EXISTS(SELECT 1 FROM assets.assets
       WHERE owner_id=$1 AND serial=$2 AND serial<>''
       AND ($3::uuid IS NULL OR id<>$3::uuid)) AS duplicate`,
      [owner.toLowerCase(), serial, excludeId ?? null],
    );
    if (typeof result.rows[0]?.duplicate !== 'boolean')
      throw new Error('asset_serial_check_missing');
    return { duplicate: result.rows[0].duplicate };
  }

  /** Aggregate the full owner inventory in one statement, independently of list filters. */
  async overview(owner: string) {
    this.owner(owner);
    const result = await this.database.pool.query<AssetOverviewRow>(
      `SELECT category, status, count(*)::text AS count
       FROM assets.assets WHERE owner_id=$1
       GROUP BY category, status ORDER BY category, status LIMIT $2`,
      [owner.toLowerCase(), ASSET_OVERVIEW_MAX_CATEGORIES * 4 + 1],
    );
    return buildAssetOverview(result.rows);
  }

  /** Read the entire bounded owner inventory in one PostgreSQL statement snapshot. */
  async snapshot(owner: string): Promise<AssetSnapshot> {
    this.owner(owner);
    const result = await this.database.pool.query<AssetSnapshot>(
      `SELECT to_char(statement_timestamp() AT TIME ZONE 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "exportedAt",
        COALESCE((SELECT json_agg(record) FROM (
          SELECT ${projection} FROM assets.assets WHERE owner_id=$1
          ORDER BY updated_at DESC,id DESC LIMIT $2
        ) record), '[]'::json) AS records`,
      [owner.toLowerCase(), ASSET_EXPORT_MAX_RECORDS + 1],
    );
    if (!result.rows[0]) throw new Error('asset_snapshot_missing');
    return result.rows[0];
  }

  /** Store one new asset without deduplicating user labels or serial numbers. */
  async create(owner: string, input: AssetInputDto): Promise<AssetRecord> {
    this.owner(owner);
    const result = await this.database.pool.query<AssetRecord>(
      `INSERT INTO assets.assets (id,owner_id,name,category,serial,status,notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING ${projection}`,
      [
        randomUUID(),
        owner.toLowerCase(),
        input.name,
        input.category,
        input.serial,
        input.status,
        input.notes,
      ],
    );
    if (!result.rows[0]) throw new Error('asset_create_missing_record');
    return result.rows[0];
  }

  /** Atomically replace only when ID, authenticated owner and expected version match. */
  async update(
    owner: string,
    id: string,
    version: number,
    input: AssetInputDto,
  ) {
    this.owner(owner);
    const result = await this.database.pool.query<AssetRecord>(
      `UPDATE assets.assets SET name=$4,category=$5,serial=$6,status=$7,notes=$8,
       version=version+1,updated_at=clock_timestamp()
       WHERE owner_id=$1 AND id=$2 AND version=$3 RETURNING ${projection}`,
      [
        owner.toLowerCase(),
        id,
        version,
        input.name,
        input.category,
        input.serial,
        input.status,
        input.notes,
      ],
    );
    return result.rows[0] ?? null;
  }
}
