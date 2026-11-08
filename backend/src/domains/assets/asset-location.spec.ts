import { BadRequestException } from '@nestjs/common';
import {
  normalizeAssetLocation,
  validateAssetLocationUpdate,
} from './asset-location';

describe('manual asset location contract', () => {
  it.each([null, 'Office', 'Kho thiết bị', '%_room', 'x'.repeat(120)])(
    'accepts explicit location %j',
    (location) => {
      expect(normalizeAssetLocation(location)).toBe(location);
    },
  );
  it('trims edges without changing internal whitespace or input', () => {
    const input = { version: 1, location: '  Room  A  ' };
    const result = validateAssetLocationUpdate(input);
    expect(result).toEqual({ version: 1, location: 'Room  A' });
    expect(input.location).toBe('  Room  A  ');
    expect(Object.isFrozen(result)).toBe(true);
  });
  it.each([
    '',
    '  ',
    3,
    false,
    undefined,
    [],
    {},
    'x'.repeat(121),
    'Room\nA',
    'Room\tA',
    'Room\u0000A',
    'Room\u007fA',
    '\ud800',
  ])('rejects invalid label %j', (location) => {
    expect(() => normalizeAssetLocation(location)).toThrow(BadRequestException);
  });
  it.each([
    null,
    [],
    {},
    { location: 'Office' },
    { version: 1 },
    { version: '1', location: null },
    { version: 0, location: null },
    { version: 1.5, location: null },
    { version: 2147483647, location: null },
    { version: 1, location: null, owner: 'other' },
    Object.create({ version: 1, location: 'Office' }),
  ])('rejects incomplete or unsafe updates %j', (value) => {
    expect(() => validateAssetLocationUpdate(value)).toThrow(
      BadRequestException,
    );
  });
  it('accepts explicit clearing and the last incrementable version', () => {
    expect(
      validateAssetLocationUpdate({ version: 2147483646, location: null }),
    ).toEqual({ version: 2147483646, location: null });
  });
});
