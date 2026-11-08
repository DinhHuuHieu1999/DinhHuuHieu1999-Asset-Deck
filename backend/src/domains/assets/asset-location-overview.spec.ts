import { buildAssetLocationOverview } from './asset-location-overview';

describe('location overview snapshot', () => {
  it('returns complete empty inventory', () => {
    expect(buildAssetLocationOverview([])).toEqual({
      complete: true,
      total: 0,
      unknown: 0,
      locations: [],
    });
  });
  it('keeps null, case and literal labels distinct', () => {
    expect(
      buildAssetLocationOverview([
        { location: null, count: '2' },
        { location: 'Room %_1', count: '3' },
        { location: 'room %_1', count: '1' },
      ]),
    ).toEqual({
      complete: true,
      total: 6,
      unknown: 2,
      locations: [
        { location: 'Room %_1', count: 3 },
        { location: 'room %_1', count: 1 },
      ],
    });
  });
  it.each(['0', '-1', '01', '1.5', 'NaN', '9007199254740992'])(
    'rejects unsafe count %s',
    (count) => {
      expect(() =>
        buildAssetLocationOverview([{ location: null, count }]),
      ).toThrow();
    },
  );
  it('rejects overflow of the total', () => {
    expect(() =>
      buildAssetLocationOverview([
        { location: null, count: '9007199254740991' },
        { location: 'A', count: '1' },
      ]),
    ).toThrow();
  });
  it('rejects duplicate or unnormalized labels', () => {
    expect(() =>
      buildAssetLocationOverview([
        { location: null, count: '1' },
        { location: null, count: '1' },
      ]),
    ).toThrow();
    expect(() =>
      buildAssetLocationOverview([{ location: ' A ', count: '1' }]),
    ).toThrow();
  });
  it('accepts the bound but refuses partial output beyond it', () => {
    const rows = Array.from({ length: 1000 }, (_, i) => ({
      location: String(i),
      count: '1',
    }));
    expect(buildAssetLocationOverview(rows).total).toBe(1000);
    expect(() =>
      buildAssetLocationOverview([...rows, { location: 'extra', count: '1' }]),
    ).toThrow();
  });
});
