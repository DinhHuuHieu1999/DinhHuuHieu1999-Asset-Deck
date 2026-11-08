import { BadRequestException } from '@nestjs/common';
import { isAssetCheckEnabled } from './asset-check';

/** Accepted inventory sort modes; omitted input preserves legacy ordering. */
export const ASSET_SORTS = ['updated_desc', 'name_asc'] as const;
export type AssetSort = (typeof ASSET_SORTS)[number];

/** Return only fixed SQL fragments; untrusted input is never interpolated. */
export function assetOrderBy(sort: unknown = 'updated_desc'): string {
  if (sort === 'updated_desc') return 'updated_at DESC,id DESC';
  if (sort === 'name_asc') return 'name COLLATE "C" ASC,id ASC';
  throw new Error('invalid_asset_sort');
}

/** Extended list-only modes; legacy selection exports keep ASSET_SORTS unchanged. */
export const ASSET_LIST_SORTS = [...ASSET_SORTS, 'checked_asc'] as const;
export type AssetListSort = (typeof ASSET_LIST_SORTS)[number];

/** Order filtered rows before paging; optional schema is never referenced when off. */
export function assetListOrderBy(sort: unknown = 'updated_desc'): string {
  if (sort === 'checked_asc') {
    if (!isAssetCheckEnabled())
      throw new BadRequestException('Check-date sorting is unavailable');
    return 'last_checked_on ASC NULLS LAST,id ASC';
  }
  return assetOrderBy(sort);
}
