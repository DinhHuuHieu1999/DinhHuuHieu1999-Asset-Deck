/** Accepted inventory sort modes; omitted input preserves legacy ordering. */
export const ASSET_SORTS = ['updated_desc', 'name_asc'] as const;
export type AssetSort = (typeof ASSET_SORTS)[number];

/** Return only fixed SQL fragments; untrusted input is never interpolated. */
export function assetOrderBy(sort: unknown = 'updated_desc'): string {
  if (sort === 'updated_desc') return 'updated_at DESC,id DESC';
  if (sort === 'name_asc') return 'name COLLATE "C" ASC,id ASC';
  throw new Error('invalid_asset_sort');
}
