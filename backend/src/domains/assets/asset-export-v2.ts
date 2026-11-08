import { createHash } from 'node:crypto';
import { UnprocessableEntityException } from '@nestjs/common';
import {
  ASSET_EXPORT_MAX_BYTES,
  ASSET_EXPORT_MAX_RECORDS,
  buildAssetExport,
} from './asset-export';
import { isAssetCalendarDate } from './asset-dates';
import type { AssetRecord } from './assets.repository';

export interface AssetExportV2Record extends AssetRecord {
  purchasedOn: string | null;
  warrantyExpiresOn: string | null;
}
export interface AssetExportV2Snapshot {
  exportedAt: string;
  records: AssetExportV2Record[];
}

/** Serialize complete date-aware snapshots without changing the legacy v1 envelope. */
export function buildAssetExportV2(snapshot: AssetExportV2Snapshot) {
  if (snapshot.records.length > ASSET_EXPORT_MAX_RECORDS) {
    throw new UnprocessableEntityException(
      'Inventory exceeds 500 assets; no partial export was produced',
    );
  }
  // Reuse the explicit v1 public-field projection, never spread database records.
  const base = JSON.parse(buildAssetExport(snapshot).payload) as {
    exportedAt: string;
    complete: true;
    recordCount: number;
    records: AssetRecord[];
  };
  const records = base.records.map((record, index) => {
    const { purchasedOn, warrantyExpiresOn } = snapshot.records[index];
    if (
      (purchasedOn !== null &&
        (!isAssetCalendarDate(purchasedOn) || purchasedOn.length !== 10)) ||
      (warrantyExpiresOn !== null &&
        (!isAssetCalendarDate(warrantyExpiresOn) ||
          warrantyExpiresOn.length !== 10)) ||
      (typeof purchasedOn === 'string' &&
        typeof warrantyExpiresOn === 'string' &&
        warrantyExpiresOn < purchasedOn)
    ) {
      throw new Error('invalid_asset_export_dates');
    }
    return { ...record, purchasedOn, warrantyExpiresOn };
  });
  const payload = JSON.stringify({ ...base, records });
  const envelope = {
    format: 'asset-desk-inventory' as const,
    schemaVersion: 2 as const,
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
