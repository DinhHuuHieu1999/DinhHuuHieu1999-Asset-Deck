import { BadRequestException } from '@nestjs/common';
import { isAssetCalendarDate } from './asset-dates';

export type AssetWarrantyFilter = 'expired' | 'expiring_soon';
export interface AssetWarrantyWindow {
  readonly filter: AssetWarrantyFilter;
  readonly asOf: string;
  readonly through: string;
}

/** Resolve a bounded UTC calendar window; expiry today is not expired. */
export function assetWarrantyWindow(
  filter: unknown,
  asOf: unknown = '',
  now: Date = new Date(),
): Readonly<AssetWarrantyWindow> {
  if (filter !== 'expired' && filter !== 'expiring_soon') {
    throw new BadRequestException('Invalid warranty filter');
  }
  const day = asOf === '' ? now.toISOString().slice(0, 10) : asOf;
  if (
    typeof day !== 'string' ||
    day.length !== 10 ||
    !isAssetCalendarDate(day)
  ) {
    throw new BadRequestException('Invalid warranty reference date');
  }
  // Explicit full-year construction avoids JavaScript's 0..99 -> 1900 offset.
  const end = new Date(0);
  end.setUTCFullYear(
    Number(day.slice(0, 4)),
    Number(day.slice(5, 7)) - 1,
    Number(day.slice(8, 10)),
  );
  end.setUTCHours(0, 0, 0, 0);
  end.setUTCDate(end.getUTCDate() + 30);
  const through =
    end.getUTCFullYear() > 9999 ? '9999-12-31' : end.toISOString().slice(0, 10);
  return Object.freeze({ filter, asOf: day, through });
}
