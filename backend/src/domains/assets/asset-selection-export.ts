import { createHash } from 'node:crypto';
import {
  BadRequestException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ASSET_EXPORT_MAX_BYTES } from './asset-export';
import {
  buildAssetExportV3,
  type AssetExportV3Snapshot,
} from './asset-export-v3';
import { normalizeAssetLocation } from './asset-location';
import { ASSET_SORTS, assetOrderBy, type AssetSort } from './asset-sort';
import {
  assetWarrantyWindow,
  type AssetWarrantyWindow,
} from './asset-warranty';
import { ASSET_STATUSES, type AssetStatus } from './assets.dto';

export interface AssetSelectionScope {
  q: string;
  status: AssetStatus | '';
  category: string;
  locationMode: 'all' | 'unknown' | 'exact';
  location: string | null;
  sort: AssetSort;
  warranty: Readonly<AssetWarrantyWindow> | null;
}

/** Reject ambiguous scope metadata before querying or serializing a selection. */
export function validateAssetSelectionScope(
  scope: AssetSelectionScope,
): AssetSelectionScope {
  for (const [value, max] of [
    [scope.q, 120],
    [scope.category, 64],
  ] as const) {
    if (
      typeof value !== 'string' ||
      value !== value.trim() ||
      value.length > max ||
      value.includes('\0')
    ) {
      throw new BadRequestException('Invalid selection text');
    }
  }
  if (!['', ...ASSET_STATUSES].includes(scope.status))
    throw new BadRequestException('Invalid selection status');
  if (!ASSET_SORTS.includes(scope.sort))
    throw new BadRequestException('Invalid selection sort');
  assetOrderBy(scope.sort);
  if (
    !['all', 'unknown', 'exact'].includes(scope.locationMode) ||
    (scope.locationMode === 'exact'
      ? normalizeAssetLocation(scope.location) !== scope.location ||
        scope.location === null
      : scope.location !== null)
  ) {
    throw new BadRequestException('Invalid selection location');
  }
  let warranty: Readonly<AssetWarrantyWindow> | null = null;
  if (scope.warranty !== null) {
    if (!scope.warranty || !scope.warranty.asOf)
      throw new BadRequestException('Selection requires a reference date');
    warranty = assetWarrantyWindow(scope.warranty.filter, scope.warranty.asOf);
    if (warranty.through !== scope.warranty.through)
      throw new BadRequestException('Invalid selection warranty window');
  }
  return {
    q: scope.q,
    status: scope.status,
    category: scope.category,
    locationMode: scope.locationMode,
    location: scope.location,
    sort: scope.sort,
    warranty,
  };
}

/** Serialize every matched row, never representing a selection as an account backup. */
export function buildAssetSelectionExport(
  snapshot: AssetExportV3Snapshot,
  scope: AssetSelectionScope,
) {
  const filters = validateAssetSelectionScope(scope);
  // Reuse only the validated public-field projection. The full-catalog envelope is discarded.
  const base = JSON.parse(buildAssetExportV3(snapshot).payload) as {
    exportedAt: string;
    recordCount: number;
    records: unknown[];
  };
  const payload = JSON.stringify({
    exportedAt: base.exportedAt,
    scope: 'filtered-selection',
    allMatchesIncluded: true,
    filters,
    recordCount: base.recordCount,
    records: base.records,
  });
  const envelope = {
    format: 'asset-desk-inventory-selection' as const,
    schemaVersion: 1 as const,
    payload,
    sha256: createHash('sha256').update(payload, 'utf8').digest('hex'),
  };
  if (
    Buffer.byteLength(JSON.stringify(envelope), 'utf8') > ASSET_EXPORT_MAX_BYTES
  ) {
    throw new UnprocessableEntityException(
      'Selection exceeds 1 MiB; no partial export was produced',
    );
  }
  return envelope;
}
