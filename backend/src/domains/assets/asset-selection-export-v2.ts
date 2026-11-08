import { createHash } from 'node:crypto';
import {
  BadRequestException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ASSET_EXPORT_MAX_BYTES } from './asset-export';
import { isAssetCalendarDate } from './asset-dates';
import type { AssetExportV3Record } from './asset-export-v3';
import {
  buildAssetSelectionExport,
  validateAssetSelectionScope,
  type AssetSelectionScope,
} from './asset-selection-export';

export type AssetSelectionCheck =
  | { mode: 'all' | 'unknown' }
  | { mode: 'before' | 'on_or_after'; cutoff: string };
export interface AssetSelectionScopeV2 extends AssetSelectionScope {
  check: AssetSelectionCheck;
}
export interface AssetSelectionRecordV2 extends AssetExportV3Record {
  lastCheckedDate: string | null;
}

/** Validate an exact tagged check predicate without inventing a reference date. */
export function validateSelectionCheck(value: unknown): AssetSelectionCheck {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new BadRequestException('Invalid selection check filter');
  const v = value as Record<string, unknown>;
  const keys = Object.keys(v);
  if ((v.mode === 'all' || v.mode === 'unknown') && keys.length === 1)
    return { mode: v.mode };
  if (
    (v.mode === 'before' || v.mode === 'on_or_after') &&
    keys.length === 2 &&
    keys.includes('cutoff') &&
    typeof v.cutoff === 'string' &&
    isAssetCalendarDate(v.cutoff)
  )
    return { mode: v.mode, cutoff: v.cutoff };
  throw new BadRequestException('Invalid selection check filter');
}

/** Serialize a bounded selection snapshot with explicit manual check dates. */
export function buildAssetSelectionExportV2(
  snapshot: { exportedAt: string; records: AssetSelectionRecordV2[] },
  scope: AssetSelectionScopeV2,
) {
  const expected = [
    'q',
    'status',
    'category',
    'locationMode',
    'location',
    'sort',
    'warranty',
    'check',
  ];
  if (
    Object.keys(scope).length !== expected.length ||
    !expected.every((k) => Object.hasOwn(scope, k))
  )
    throw new BadRequestException('Invalid selection v2 scope');
  const check = validateSelectionCheck(scope.check);
  const filters = { ...validateAssetSelectionScope(scope), check };
  const base = JSON.parse(
    buildAssetSelectionExport(snapshot, scope).payload,
  ) as {
    exportedAt: string;
    records: Record<string, unknown>[];
    recordCount: number;
  };
  const records = base.records.map((record, i) => {
    const date = snapshot.records[i].lastCheckedDate;
    if (
      date !== null &&
      (typeof date !== 'string' || !isAssetCalendarDate(date))
    )
      throw new Error('invalid_selection_check_date');
    if (
      (check.mode === 'unknown' && date !== null) ||
      (check.mode === 'before' && (date === null || date >= check.cutoff)) ||
      (check.mode === 'on_or_after' && (date === null || date < check.cutoff))
    )
      throw new Error('selection_check_scope_mismatch');
    return { ...record, lastCheckedDate: date };
  });
  const payload = JSON.stringify({
    exportedAt: base.exportedAt,
    scope: 'filtered-selection',
    allMatchesIncluded: true,
    filters,
    recordCount: base.recordCount,
    records,
  });
  const envelope = {
    format: 'asset-desk-inventory-selection' as const,
    schemaVersion: 2 as const,
    payload,
    sha256: createHash('sha256').update(payload, 'utf8').digest('hex'),
  };
  if (
    Buffer.byteLength(JSON.stringify(envelope), 'utf8') > ASSET_EXPORT_MAX_BYTES
  )
    throw new UnprocessableEntityException(
      'Selection exceeds 1 MiB; no partial export was produced',
    );
  return envelope;
}
