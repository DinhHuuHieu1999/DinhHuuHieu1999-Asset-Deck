import { createHash } from 'node:crypto';
import { UnprocessableEntityException } from '@nestjs/common';
import { ASSET_EXPORT_MAX_BYTES } from './asset-export';
import {
  buildAssetExportV2,
  type AssetExportV2Record,
} from './asset-export-v2';
import { normalizeAssetLocation } from './asset-location';

export interface AssetExportV3Record extends AssetExportV2Record {
  location: string | null;
}
export interface AssetExportV3Snapshot {
  exportedAt: string;
  records: AssetExportV3Record[];
}

/** Export explicit public fields with dates and canonical manual locations. */
export function buildAssetExportV3(snapshot: AssetExportV3Snapshot) {
  const base = JSON.parse(buildAssetExportV2(snapshot).payload) as {
    exportedAt: string;
    complete: true;
    recordCount: number;
    records: AssetExportV2Record[];
  };
  const records = base.records.map((record, index) => {
    const location = snapshot.records[index].location;
    if (normalizeAssetLocation(location) !== location) {
      throw new Error('invalid_asset_export_location');
    }
    return { ...record, location };
  });
  const payload = JSON.stringify({ ...base, records });
  const envelope = {
    format: 'asset-desk-inventory' as const,
    schemaVersion: 3 as const,
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
