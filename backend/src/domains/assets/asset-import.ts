// Adapted from ToolDeck prepareToolImport; no upstream runtime dependency.
import { BadRequestException, PayloadTooLargeException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { validateSync } from 'class-validator';
import { AssetInputDto } from './assets.dto';

export const ASSET_IMPORT_MAX_RECORDS = 500;
export const ASSET_IMPORT_MAX_BYTES = 1024 * 1024;
const fields = ['name', 'category', 'serial', 'status', 'notes'] as const;

export interface PreparedAssetImport {
  readonly requestId: string;
  readonly digest: string;
  readonly records: readonly Readonly<AssetInputDto>[];
}

function object(value: unknown): value is Record<string, unknown> {
  return (
    value !== null &&
    typeof value === 'object' &&
    !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype ||
      Object.getPrototypeOf(value) === null)
  );
}

function invalid(): never {
  // Never include rejected field values or validation objects in errors/logs.
  throw new BadRequestException('Invalid add-only import request');
}

/** Prepare a bounded immutable batch; performs no I/O and confers no ownership. */
export function prepareAssetImport(value: unknown): PreparedAssetImport {
  if (
    !object(value) ||
    Object.keys(value).length !== 2 ||
    !Object.hasOwn(value, 'requestId') ||
    !Object.hasOwn(value, 'records')
  )
    invalid();
  const { requestId, records } = value;
  if (
    typeof requestId !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(
      requestId,
    ) ||
    !Array.isArray(records) ||
    records.length === 0
  )
    invalid();
  if (records.length > ASSET_IMPORT_MAX_RECORDS)
    throw new PayloadTooLargeException('Import limit: 500 assets');
  const normalized = Array.from(records, (record: unknown) => {
    if (
      !object(record) ||
      Object.keys(record).length !== fields.length ||
      !fields.every(
        (field) =>
          Object.hasOwn(record, field) && typeof record[field] === 'string',
      )
    )
      invalid();
    // Copy only editable fields, in a stable order. IDs/version/owner are forbidden.
    const input = new AssetInputDto();
    for (const field of fields) {
      const text = record[field] as string;
      if (Buffer.from(text, 'utf8').toString('utf8') !== text) invalid();
      Reflect.set(input, field, text);
    }
    if (validateSync(input, { forbidUnknownValues: true }).length) invalid();
    input.name = input.name.trim();
    input.category = input.category.trim();
    input.serial = input.serial.trim();
    input.notes = input.notes.trim();
    if (!input.name || !input.category) invalid();
    return Object.freeze(input);
  });
  // The transport must additionally bound raw bytes before JSON decoding.
  if (Buffer.byteLength(JSON.stringify(value), 'utf8') > ASSET_IMPORT_MAX_BYTES)
    throw new PayloadTooLargeException('Import limit: 1 MiB');
  const payload = JSON.stringify({
    format: 'asset-desk-inventory-add-only',
    schemaVersion: 1,
    records: normalized,
  });
  return Object.freeze({
    requestId: requestId.toLowerCase(),
    digest: createHash('sha256').update(payload, 'utf8').digest('hex'),
    records: Object.freeze(normalized),
  });
}
