import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { isAssetCalendarDate } from './asset-dates';
import { ASSET_IMPORT_MAX_BYTES } from './asset-import';
import {
  prepareAssetImportV3,
  type AssetImportV3Record,
} from './asset-import-v3';

export type AssetImportV4Record = AssetImportV3Record & {
  readonly lastCheckedDate: string | null;
};
export interface PreparedAssetImportV4 {
  readonly requestId: string;
  readonly digest: string;
  readonly records: readonly AssetImportV4Record[];
}

/** Prepare a literal historical snapshot; transport validates raw JSON separately. */
export function prepareAssetImportV4(value: unknown): PreparedAssetImportV4 {
  const invalid = (): never => {
    throw new BadRequestException('Invalid add-only import v4 request');
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
    !Object.hasOwn(input, 'requestId') ||
    !Object.hasOwn(input, 'records') ||
    !Array.isArray(input.records)
  )
    return invalid();
  const dates: (string | null)[] = [];
  const projected = input.records.map((row: unknown) => {
    if (
      row === null ||
      typeof row !== 'object' ||
      Array.isArray(row) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(row))
    )
      return invalid();
    const record = row as Record<string, unknown>;
    if (
      !Object.hasOwn(record, 'lastCheckedDate') ||
      (record.lastCheckedDate !== null &&
        !isAssetCalendarDate(record.lastCheckedDate))
    )
      return invalid();
    dates.push(record.lastCheckedDate as string | null);
    const { lastCheckedDate: _date, ...base } = record;
    return base;
  });
  const base = prepareAssetImportV3({
    requestId: input.requestId,
    records: projected,
  });
  if (Buffer.byteLength(JSON.stringify(value), 'utf8') > ASSET_IMPORT_MAX_BYTES)
    throw new PayloadTooLargeException('Import limit: 1 MiB');
  const records = Object.freeze(
    base.records.map((record, index) =>
      Object.freeze({ ...record, lastCheckedDate: dates[index] }),
    ),
  );
  const payload = JSON.stringify({
    format: 'asset-desk-inventory-add-only',
    schemaVersion: 4,
    records,
  });
  return Object.freeze({
    requestId: base.requestId,
    digest: createHash('sha256').update(payload, 'utf8').digest('hex'),
    records,
  });
}
