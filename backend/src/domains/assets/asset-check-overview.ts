import {
  BadRequestException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { isAssetCalendarDate } from './asset-dates';

export interface AssetCheckOverviewRow {
  total: string;
  unknown: string;
  before: string;
  onOrAfter: string;
}

/** Refuse partial, inconsistent or unsafe aggregate counts at a strict cutoff. */
export function buildAssetCheckOverview(
  row: AssetCheckOverviewRow,
  cutoff: string,
) {
  if (!isAssetCalendarDate(cutoff))
    throw new BadRequestException('Invalid check cutoff');
  const fields = ['total', 'unknown', 'before', 'onOrAfter'] as const;
  const counts = {} as Record<(typeof fields)[number], number>;
  for (const field of fields) {
    const value = row[field];
    if (typeof value !== 'string' || !/^(0|[1-9][0-9]*)$/.test(value)) {
      throw new Error('asset_check_overview_invalid_aggregate');
    }
    const count = Number(value);
    if (!Number.isSafeInteger(count))
      throw new UnprocessableEntityException(
        'Check counts exceed the safe integer limit',
      );
    counts[field] = count;
  }
  const sum = counts.unknown + counts.before + counts.onOrAfter;
  if (!Number.isSafeInteger(sum))
    throw new UnprocessableEntityException(
      'Check counts exceed the safe integer limit',
    );
  if (sum !== counts.total)
    throw new Error('asset_check_overview_inconsistent_aggregate');
  return { complete: true as const, cutoff, ...counts };
}
