import { BadRequestException } from '@nestjs/common';

export interface AssetDatesUpdate {
  version: number;
  purchasedOn: string | null;
  warrantyExpiresOn: string | null;
}

/** Validate a date-only Gregorian label without timezone parsing or rollover. */
export function isAssetCalendarDate(value: unknown): value is string {
  if (typeof value !== 'string' || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(value))
    return false;
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(5, 7));
  const day = Number(value.slice(8, 10));
  if (year < 1 || month < 1 || month > 12 || day < 1) return false;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= days[month - 1];
}

/** Require explicit complete date replacement; never normalize invalid input silently. */
export function validateAssetDatesUpdate(
  value: unknown,
): Readonly<AssetDatesUpdate> {
  const invalid = (): never => {
    throw new BadRequestException('Invalid purchase/warranty dates');
  };
  if (
    value === null ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(value))
  )
    return invalid();
  const input = value as Record<string, unknown>;
  const fields = ['version', 'purchasedOn', 'warrantyExpiresOn'];
  if (
    Object.keys(input).length !== fields.length ||
    !fields.every((key) => Object.hasOwn(input, key))
  )
    return invalid();
  const { version, purchasedOn, warrantyExpiresOn } = input;
  if (
    typeof version !== 'number' ||
    !Number.isInteger(version) ||
    version < 1 ||
    version > 2147483646 ||
    (purchasedOn !== null && !isAssetCalendarDate(purchasedOn)) ||
    (warrantyExpiresOn !== null && !isAssetCalendarDate(warrantyExpiresOn))
  )
    return invalid();
  if (
    typeof purchasedOn === 'string' &&
    typeof warrantyExpiresOn === 'string' &&
    warrantyExpiresOn < purchasedOn
  )
    return invalid();
  return Object.freeze({
    version,
    purchasedOn,
    warrantyExpiresOn,
  }) as Readonly<AssetDatesUpdate>;
}
