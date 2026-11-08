import { BadRequestException } from '@nestjs/common';
import { isAssetCalendarDate } from './asset-dates';
import { normalizeAssetLocation } from './asset-location';
import { ASSET_LIST_SORTS } from './asset-sort';
import { ASSET_STATUSES } from './assets.dto';

export interface SavedFilterCapabilities {
  readonly location: boolean;
  readonly warranty: boolean;
  readonly check: boolean;
}

const keys = [
  'q',
  'status',
  'category',
  'sort',
  'locationMode',
  'location',
  'warranty',
  'asOf',
  'checkMode',
  'checkBefore',
  'checkOnOrAfter',
] as const;
export type SavedFilterQuery = Readonly<Record<(typeof keys)[number], string>>;

/** Validate complete schema-v1 query data without executing or rewriting dates. */
export function validateSavedFilterQuery(value: unknown): SavedFilterQuery {
  const invalid = (): never => {
    throw new BadRequestException('Invalid saved filter query');
  };
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(value))
  )
    return invalid();
  const input = value as Record<string, unknown>;
  if (
    Object.keys(input).length !== keys.length ||
    !keys.every(
      (key) => Object.hasOwn(input, key) && typeof input[key] === 'string',
    )
  )
    return invalid();
  const query = Object.fromEntries(
    keys.map((key) => [key, input[key]]),
  ) as Record<(typeof keys)[number], string>;
  if (
    keys.some((key) =>
      /[\u0000-\u001f\u007f\ud800-\udfff]/u.test(query[key]),
    ) ||
    query.q.length > 120 ||
    query.category.length > 64 ||
    !['', ...ASSET_STATUSES].includes(query.status) ||
    !(ASSET_LIST_SORTS as readonly string[]).includes(query.sort) ||
    !['all', 'exact', 'unknown'].includes(query.locationMode) ||
    !['all', 'expired', 'expiring_soon'].includes(query.warranty) ||
    !['all', 'unchecked', 'before', 'on_or_after'].includes(query.checkMode)
  )
    return invalid();
  if (query.locationMode === 'exact') {
    if (normalizeAssetLocation(query.location) !== query.location)
      return invalid();
  } else if (query.location !== '') return invalid();
  if (
    query.warranty === 'all'
      ? query.asOf !== ''
      : !isAssetCalendarDate(query.asOf)
  )
    return invalid();
  if (
    query.checkMode === 'before'
      ? !isAssetCalendarDate(query.checkBefore)
      : query.checkBefore !== ''
  )
    return invalid();
  if (
    query.checkMode === 'on_or_after'
      ? !isAssetCalendarDate(query.checkOnOrAfter)
      : query.checkOnOrAfter !== ''
  )
    return invalid();
  return Object.freeze(query);
}

/** Refuse unsupported active filters without silently weakening a saved query. */
export function assertSavedFilterCapabilities(
  query: SavedFilterQuery,
  capabilities: SavedFilterCapabilities,
): void {
  if (
    (query.locationMode !== 'all' && !capabilities.location) ||
    (query.warranty !== 'all' && !capabilities.warranty) ||
    ((query.checkMode !== 'all' || query.sort === 'checked_asc') &&
      !capabilities.check)
  ) {
    throw new BadRequestException(
      'Saved filter requires unavailable capabilities',
    );
  }
}

/** Bound a human label independently from query data and asset identity. */
export function validateSavedFilterName(value: unknown): string {
  if (
    typeof value !== 'string' ||
    !value.trim() ||
    value.trim().length > 60 ||
    /[\u0000-\u001f\u007f\ud800-\udfff]/u.test(value)
  ) {
    throw new BadRequestException('Invalid saved filter name');
  }
  return value.trim();
}
