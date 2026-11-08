import { BadRequestException } from '@nestjs/common';

export interface AssetLocationUpdate {
  version: number;
  location: string | null;
}

/** Normalize a manual label; null explicitly clears the location. */
export function normalizeAssetLocation(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== 'string') {
    throw new BadRequestException('Invalid asset location');
  }
  const location = value.trim();
  if (
    !location ||
    location.length > 120 ||
    /[\u0000-\u001f\u007f]/u.test(location) ||
    /[\ud800-\udfff]/u.test(location)
  ) {
    throw new BadRequestException('Invalid asset location');
  }
  return location;
}

/** Require an explicit replacement with the shared optimistic asset version. */
export function validateAssetLocationUpdate(
  value: unknown,
): Readonly<AssetLocationUpdate> {
  if (
    value === null ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(value))
  ) {
    throw new BadRequestException('Invalid asset location update');
  }
  const input = value as Record<string, unknown>;
  if (
    Object.keys(input).length !== 2 ||
    !Object.hasOwn(input, 'version') ||
    !Object.hasOwn(input, 'location') ||
    typeof input.version !== 'number' ||
    !Number.isInteger(input.version) ||
    input.version < 1 ||
    input.version > 2147483646
  ) {
    throw new BadRequestException('Invalid asset location update');
  }
  return Object.freeze({
    version: input.version,
    location: normalizeAssetLocation(input.location),
  });
}
