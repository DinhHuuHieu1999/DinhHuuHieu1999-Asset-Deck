import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { validateAssetDatesUpdate } from './asset-dates';
import {
  ASSET_IMPORT_MAX_BYTES,
  ASSET_IMPORT_MAX_RECORDS,
  prepareAssetImport,
} from './asset-import';
import type { AssetInputDto } from './assets.dto';

export type AssetImportV2Record = Readonly<AssetInputDto> & {
  readonly purchasedOn: string | null;
  readonly warrantyExpiresOn: string | null;
};

export interface PreparedAssetImportV2 {
  readonly requestId: string;
  readonly digest: string;
  readonly records: readonly AssetImportV2Record[];
}

const fields = [
  'name',
  'category',
  'serial',
  'status',
  'notes',
  'purchasedOn',
  'warrantyExpiresOn',
] as const;

function object(value: unknown): value is Record<string, unknown> {
  return (
    value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    [Object.prototype, null].includes(Object.getPrototypeOf(value))
  );
}

function invalid(): never {
  throw new BadRequestException('Invalid add-only import v2 request');
}

/** Prepare a version-separated immutable batch without database or transport I/O.
 * The transport must enforce raw size, Unicode and duplicate-key checks before decoding.
 */
export function prepareAssetImportV2(value: unknown): PreparedAssetImportV2 {
  if (
    !object(value) ||
    Object.keys(value).length !== 2 ||
    !Object.hasOwn(value, 'requestId') ||
    !Object.hasOwn(value, 'records') ||
    !Array.isArray(value.records)
  )
    invalid();
  if (value.records.length > ASSET_IMPORT_MAX_RECORDS)
    throw new PayloadTooLargeException('Import limit: 500 assets');
  const dates = value.records.map((row: unknown) => {
    if (
      !object(row) ||
      Object.keys(row).length !== fields.length ||
      !fields.every((field) => Object.hasOwn(row, field))
    )
      invalid();
    return validateAssetDatesUpdate({
      version: 1,
      purchasedOn: row.purchasedOn,
      warrantyExpiresOn: row.warrantyExpiresOn,
    });
  });
  const base = prepareAssetImport({
    requestId: value.requestId,
    records: value.records.map((row: Record<string, unknown>) => ({
      name: row.name,
      category: row.category,
      serial: row.serial,
      status: row.status,
      notes: row.notes,
    })),
  });
  if (Buffer.byteLength(JSON.stringify(value), 'utf8') > ASSET_IMPORT_MAX_BYTES)
    throw new PayloadTooLargeException('Import limit: 1 MiB');
  const records = Object.freeze(
    base.records.map((row, index) =>
      Object.freeze({
        ...row,
        purchasedOn: dates[index].purchasedOn,
        warrantyExpiresOn: dates[index].warrantyExpiresOn,
      }),
    ),
  );
  const payload = JSON.stringify({
    format: 'asset-desk-inventory-add-only',
    schemaVersion: 2,
    records,
  });
  return Object.freeze({
    requestId: base.requestId,
    digest: createHash('sha256').update(payload, 'utf8').digest('hex'),
    records,
  });
}
