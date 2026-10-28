// Adapted from ToolDeck ToolboxImportRepository; v3 preserves dates and location in the same receipt transaction.
import { ConflictException, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { isAccountId } from '../auth/account.repository';
import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { prepareAssetImportV3 } from './asset-import-v3';

interface StoredReceipt {
  digest: string;
  recordIds: string[];
}

/** Add-only transaction repository; registered only by the independently opt-in module. */
export class AssetImportV3Repository {
  constructor(private readonly database: PostgresDatabase) {}

  /** Read-only prerequisite probe; never creates or repairs schema. */
  async assertReady(): Promise<void> {
    try {
      await this.database.pool.query(
        `SELECT id,owner_id,name,category,serial,status,notes,purchased_on,warranty_expires_on,location
         FROM assets.assets LIMIT 0`,
      );
      await this.database.pool.query(
        `SELECT owner_id,request_id,digest,record_ids,created_at
         FROM assets.import_receipts LIMIT 0`,
      );
    } catch {
      throw new ServiceUnavailableException('Asset import schema is not ready');
    }
  }

  /** Validate the whole batch before acquiring a connection; replay never inserts again. */
  async importBatch(owner: string, input: unknown) {
    if (!isAccountId(owner)) throw new Error('invalid_asset_owner');
    owner = owner.toLowerCase();
    const prepared = prepareAssetImportV3(input);
    const ids = prepared.records.map(() => randomUUID());
    let client: PoolClient | undefined;
    let broken = false;
    let commitAttempted = false;
    try {
      client = await this.database.pool.connect();
      await client.query('BEGIN ISOLATION LEVEL READ COMMITTED');
      // A conflicting INSERT waits for the other transaction; the next READ COMMITTED
      // statement then sees its durable receipt. A rollback allows this insert to win.
      const claimed = await client.query(
        `INSERT INTO assets.import_receipts(owner_id,request_id,digest,record_ids)
         VALUES($1,$2,$3,$4::uuid[]) ON CONFLICT(owner_id,request_id) DO NOTHING
         RETURNING request_id`,
        [owner, prepared.requestId, prepared.digest, ids],
      );
      let recordIds: string[];
      if (claimed.rows.length === 1) {
        const records = prepared.records.map((record, index) => ({
          ...record,
          id: ids[index],
        }));
        const inserted = await client.query(
          `INSERT INTO assets.assets(id,owner_id,name,category,serial,status,notes,purchased_on,warranty_expires_on,location)
           SELECT x.id,$1,x.name,x.category,x.serial,x.status,x.notes,x."purchasedOn",x."warrantyExpiresOn",x.location
           FROM jsonb_to_recordset($2::jsonb) AS x(id uuid,name text,category text,serial text,status text,notes text,"purchasedOn" date,"warrantyExpiresOn" date,location text)`,
          [owner, JSON.stringify(records)],
        );
        if (inserted.rowCount !== prepared.records.length)
          throw new Error('incomplete_import_insert');
        recordIds = ids;
      } else {
        const existing = await client.query<StoredReceipt>(
          `SELECT digest,record_ids AS "recordIds" FROM assets.import_receipts
           WHERE owner_id=$1 AND request_id=$2`,
          [owner, prepared.requestId],
        );
        const receipt = existing.rows[0];
        if (!receipt) throw new Error('missing_import_receipt');
        if (receipt.digest !== prepared.digest)
          throw new ConflictException(
            'Import request key already used for different content',
          );
        if (
          !Array.isArray(receipt.recordIds) ||
          receipt.recordIds.length !== prepared.records.length ||
          new Set(receipt.recordIds).size !== receipt.recordIds.length ||
          receipt.recordIds.some(
            (id) =>
              typeof id !== 'string' ||
              !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(
                id,
              ),
          )
        )
          throw new Error('invalid_import_receipt');
        recordIds = receipt.recordIds;
      }
      commitAttempted = true;
      await client.query('COMMIT');
      return {
        requestId: prepared.requestId,
        recordCount: recordIds.length,
        recordIds,
      };
    } catch (error) {
      broken = commitAttempted;
      if (client) {
        try {
          await client.query('ROLLBACK');
        } catch {
          broken = true;
        }
      }
      if (error instanceof ConflictException) throw error;
      // COMMIT acknowledgement can be lost after success. Never issue a new key or
      // retry here; the caller must retain the same key for an explicit retry.
      throw new ServiceUnavailableException(
        'Import outcome unavailable; retain the same request key',
      );
    } finally {
      client?.release(broken);
    }
  }
}
