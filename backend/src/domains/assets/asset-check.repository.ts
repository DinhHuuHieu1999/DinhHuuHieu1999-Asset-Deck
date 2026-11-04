import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { isAccountId } from '../auth/account.repository';
import { validateAssetCheckUpdate, type AssetCheckUpdate } from './asset-check';

export interface AssetCheckRecord {
  id: string;
  version: number;
  lastCheckedOn: string | null;
}
const projection = `id,version,to_char(last_checked_on,'YYYY-MM-DD') AS "lastCheckedOn"`;

/** Optional manual check dates share the existing owner and optimistic version. */
export class AssetCheckRepository {
  constructor(private readonly database: PostgresDatabase) {}

  private owner(value: string): string {
    if (!isAccountId(value)) throw new Error('invalid_asset_owner');
    return value.toLowerCase();
  }

  /** Read required schema only; never create or migrate it during startup. */
  async ready(): Promise<void> {
    await this.database.pool.query(
      `SELECT ${projection},owner_id FROM assets.assets LIMIT 0`,
    );
  }

  /** Return the same absent result for missing and other-owner records. */
  async read(owner: string, id: string): Promise<AssetCheckRecord | null> {
    const result = await this.database.pool.query<AssetCheckRecord>(
      `SELECT ${projection} FROM assets.assets WHERE owner_id=$1 AND id=$2`,
      [this.owner(owner), id],
    );
    return result.rows[0] ?? null;
  }

  /** Make one shared-version write; never retry an uncertain result. */
  async update(
    owner: string,
    id: string,
    input: Readonly<AssetCheckUpdate>,
  ): Promise<AssetCheckRecord | null> {
    const account = this.owner(owner);
    const checked = validateAssetCheckUpdate(input);
    const result = await this.database.pool.query<AssetCheckRecord>(
      `UPDATE assets.assets SET last_checked_on=$4::date,version=version+1,updated_at=clock_timestamp()
       WHERE owner_id=$1 AND id=$2 AND version=$3 RETURNING ${projection}`,
      [account, id, checked.version, checked.lastCheckedOn],
    );
    return result.rows[0] ?? null;
  }
}
