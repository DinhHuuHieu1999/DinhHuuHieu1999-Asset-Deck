import { BadRequestException } from '@nestjs/common';
import { isAssetCalendarDate } from './asset-dates';

export interface AssetCheckUpdate {
  version: number;
  lastCheckedOn: string | null;
}

/** Validate an explicit manual check date against the server's UTC calendar day. */
export function validateAssetCheckUpdate(
  value: unknown,
  asOf: string = new Date().toISOString().slice(0, 10),
): Readonly<AssetCheckUpdate> {
  if (!isAssetCalendarDate(asOf))
    throw new Error('invalid_check_reference_date');
  const invalid = (): never => {
    throw new BadRequestException('Invalid last checked date');
  };
  if (
    value === null ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(value))
  )
    return invalid();
  const input = value as Record<string, unknown>;
  if (
    Object.keys(input).length !== 2 ||
    !Object.hasOwn(input, 'version') ||
    !Object.hasOwn(input, 'lastCheckedOn') ||
    typeof input.version !== 'number' ||
    !Number.isInteger(input.version) ||
    input.version < 1 ||
    input.version > 2147483646 ||
    (input.lastCheckedOn !== null &&
      (!isAssetCalendarDate(input.lastCheckedOn) || input.lastCheckedOn > asOf))
  )
    return invalid();
  return Object.freeze({
    version: input.version,
    lastCheckedOn: input.lastCheckedOn as string | null,
  });
}

/** Disabled by default; refuse ambiguous feature configuration. */
export function isAssetCheckEnabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_CHECK_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error('ASSET_CHECK_ENABLED must be true or false');
}

/** Fixed SQL fragment only; disabled/invalid filters fail before any query. */
export function assetCheckPredicate(mode: unknown): string {
  if (mode === undefined || mode === 'all') return '';
  if (mode !== 'unchecked')
    throw new BadRequestException('Invalid check filter');
  if (!isAssetCheckEnabled())
    throw new BadRequestException('Check filtering is unavailable');
  return 'AND last_checked_on IS NULL';
}

/** Validate a fixed filter and return a bound cutoff, never interpolated date SQL. */
export function assetCheckFilter(
  mode: unknown,
  cutoff: unknown = '',
  parameter = 1,
): Readonly<{ sql: string; values: string[] }> {
  if (mode !== 'before') {
    if (cutoff !== '') throw new BadRequestException('Unexpected check cutoff');
    return { sql: assetCheckPredicate(mode), values: [] };
  }
  if (!isAssetCheckEnabled())
    throw new BadRequestException('Check filtering is unavailable');
  if (!isAssetCalendarDate(cutoff))
    throw new BadRequestException('Invalid check cutoff');
  if (!Number.isInteger(parameter) || parameter < 1 || parameter > 11)
    throw new Error('invalid_check_parameter');
  return { sql: `AND last_checked_on < $${parameter}::date`, values: [cutoff] };
}
