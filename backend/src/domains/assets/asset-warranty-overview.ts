import { UnprocessableEntityException } from '@nestjs/common';
import type { AssetWarrantyWindow } from './asset-warranty';

export interface AssetWarrantyOverviewRow {
  total: string;
  expired: string;
  expiringSoon: string;
  later: string;
  unknown: string;
}

/** Validate complete aggregate counts before converting PostgreSQL bigint text. */
export function buildAssetWarrantyOverview(
  row: AssetWarrantyOverviewRow,
  window: Readonly<Pick<AssetWarrantyWindow, 'asOf' | 'through'>>,
) {
  const fields = [
    'total',
    'expired',
    'expiringSoon',
    'later',
    'unknown',
  ] as const;
  const counts = {} as Record<(typeof fields)[number], number>;
  for (const field of fields) {
    const value = row[field];
    if (typeof value !== 'string' || !/^(0|[1-9][0-9]*)$/.test(value)) {
      throw new Error('asset_warranty_overview_invalid_aggregate');
    }
    const count = Number(value);
    if (!Number.isSafeInteger(count)) {
      throw new UnprocessableEntityException(
        'Warranty count exceeds the safe integer limit; no partial overview is returned',
      );
    }
    counts[field] = count;
  }
  const sum =
    counts.expired + counts.expiringSoon + counts.later + counts.unknown;
  if (!Number.isSafeInteger(sum)) {
    throw new UnprocessableEntityException(
      'Warranty count exceeds the safe integer limit; no partial overview is returned',
    );
  }
  if (sum !== counts.total) {
    throw new Error('asset_warranty_overview_inconsistent_aggregate');
  }
  return {
    complete: true as const,
    asOf: window.asOf,
    through: window.through,
    ...counts,
  };
}
