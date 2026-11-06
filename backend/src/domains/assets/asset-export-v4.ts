import { createHash } from 'node:crypto';
import { UnprocessableEntityException } from '@nestjs/common';
import { ASSET_EXPORT_MAX_BYTES } from './asset-export';
import { isAssetCalendarDate } from './asset-dates';
import {
  buildAssetExportV3,
  type AssetExportV3Record,
} from './asset-export-v3';

export interface AssetExportV4Record extends AssetExportV3Record {
  lastCheckedDate: string | null;
}
export interface AssetExportV4Snapshot {
  exportedAt: string;
  records: AssetExportV4Record[];
}

/** Serialize a complete public snapshot including explicit manual check dates. */
export function buildAssetExportV4(snapshot: AssetExportV4Snapshot) {
  const base = JSON.parse(buildAssetExportV3(snapshot).payload) as {
    exportedAt: string;
    complete: true;
    recordCount: number;
    records: AssetExportV3Record[];
  };
  const records = base.records.map((record, index) => {
    const date = snapshot.records[index].lastCheckedDate;
    if (
      date !== null &&
      (typeof date !== 'string' || !isAssetCalendarDate(date))
    )
      throw new Error('invalid_asset_export_check_date');
    return { ...record, lastCheckedDate: date };
  });
  const payload = JSON.stringify({ ...base, records });
  const envelope = {
    format: 'asset-desk-inventory' as const,
    schemaVersion: 4 as const,
    payload,
    sha256: createHash('sha256').update(payload, 'utf8').digest('hex'),
  };
  if (
    Buffer.byteLength(JSON.stringify(envelope), 'utf8') > ASSET_EXPORT_MAX_BYTES
  )
    throw new UnprocessableEntityException(
      'Inventory export exceeds 1 MiB; no partial export was produced',
    );
  return envelope;
}
