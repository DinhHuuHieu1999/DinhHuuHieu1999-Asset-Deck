import { createHash } from 'node:crypto';
import { UnprocessableEntityException } from '@nestjs/common';
import type { AssetRecord } from './assets.repository';

export const ASSET_EXPORT_MAX_RECORDS = 500;
export const ASSET_EXPORT_MAX_BYTES = 1024 * 1024;

export interface AssetSnapshot {
  exportedAt: string;
  records: AssetRecord[];
}

/** Serialize exact UTF-8 payload bytes; a checksum is not proof of authenticity. */
export function buildAssetExport(snapshot: AssetSnapshot) {
  if (snapshot.records.length > ASSET_EXPORT_MAX_RECORDS) {
    throw new UnprocessableEntityException(
      'Inventory exceeds 500 assets; no partial export was produced',
    );
  }
  // Project explicitly: owner IDs or future internal fields must never leak.
  const records = snapshot.records.map((record) => ({
    id: record.id,
    name: record.name,
    category: record.category,
    serial: record.serial,
    status: record.status,
    notes: record.notes,
    version: record.version,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  }));
  const payload = JSON.stringify({
    exportedAt: snapshot.exportedAt,
    complete: true,
    recordCount: records.length,
    records,
  });
  const envelope = {
    format: 'asset-desk-inventory' as const,
    schemaVersion: 1 as const,
    payload,
    sha256: createHash('sha256').update(payload, 'utf8').digest('hex'),
  };
  if (
    Buffer.byteLength(JSON.stringify(envelope), 'utf8') > ASSET_EXPORT_MAX_BYTES
  ) {
    throw new UnprocessableEntityException(
      'Inventory export exceeds 1 MiB; no partial export was produced',
    );
  }
  return envelope;
}
