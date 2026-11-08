import { UnprocessableEntityException } from '@nestjs/common';

export const ASSET_OVERVIEW_MAX_CATEGORIES = 200;
const statuses = ['in_use', 'stored', 'repair', 'retired'] as const;
type Status = (typeof statuses)[number];
export interface AssetOverviewRow {
  category: string;
  status: string;
  count: string;
}

/** Validate bounded aggregate rows without presenting truncated counts as complete. */
export function buildAssetOverview(rows: AssetOverviewRow[]) {
  const byStatus: Record<Status, number> = {
    in_use: 0,
    stored: 0,
    repair: 0,
    retired: 0,
  };
  const categories = new Map<string, number>();
  const seen = new Set<string>();
  let total = 0;
  for (const row of rows) {
    if (
      typeof row.category !== 'string' ||
      !row.category.trim() ||
      Array.from(row.category).length > 64 ||
      row.category.includes('\0') ||
      !statuses.includes(row.status as Status) ||
      typeof row.count !== 'string' ||
      !/^[1-9][0-9]*$/.test(row.count)
    ) {
      throw new Error('asset_overview_invalid_aggregate');
    }
    const key = JSON.stringify([row.category, row.status]);
    if (seen.has(key)) throw new Error('asset_overview_duplicate_aggregate');
    seen.add(key);
    const count = Number(row.count);
    total += count;
    if (!Number.isSafeInteger(count) || !Number.isSafeInteger(total)) {
      throw new Error('asset_overview_count_overflow');
    }
    byStatus[row.status as Status] += count;
    categories.set(row.category, (categories.get(row.category) ?? 0) + count);
    if (categories.size > ASSET_OVERVIEW_MAX_CATEGORIES) {
      throw new UnprocessableEntityException(
        'Overview category limit reached; no partial overview is returned',
      );
    }
  }
  return {
    complete: true as const,
    total,
    byStatus,
    byCategory: Array.from(categories, ([category, count]) => ({
      category,
      count,
    })).sort((a, b) =>
      a.category < b.category ? -1 : a.category > b.category ? 1 : 0,
    ),
  };
}
