import { UnprocessableEntityException } from '@nestjs/common';
import { normalizeAssetLocation } from './asset-location';

export interface AssetLocationOverviewRow {
  location: string | null;
  count: string;
}

/** Validate a complete grouped snapshot; never return truncated or unsafe counts. */
export function buildAssetLocationOverview(rows: AssetLocationOverviewRow[]) {
  const locations: { location: string; count: number }[] = [];
  const seen = new Set<string | null>();
  let total = 0;
  let unknown = 0;
  for (const row of rows) {
    if (
      seen.has(row.location) ||
      normalizeAssetLocation(row.location) !== row.location
    )
      throw new Error('asset_location_overview_invalid_group');
    seen.add(row.location);
    if (typeof row.count !== 'string' || !/^[1-9][0-9]*$/.test(row.count))
      throw new Error('asset_location_overview_invalid_count');
    const count = Number(row.count);
    total += count;
    if (!Number.isSafeInteger(count) || !Number.isSafeInteger(total))
      throw new UnprocessableEntityException(
        'Location overview count exceeds safe integer limit',
      );
    if (row.location === null) unknown = count;
    else locations.push({ location: row.location, count });
    if (locations.length > 1000)
      throw new UnprocessableEntityException(
        'Too many locations; no partial overview is returned',
      );
  }
  return { complete: true as const, total, unknown, locations };
}
