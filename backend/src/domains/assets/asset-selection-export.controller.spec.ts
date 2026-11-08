import {
  assetSelectionQuery,
  AssetSelectionExportController,
} from './asset-selection-export.controller';

describe('selection query and controller', () => {
  it('canonicalizes literal filters without accepting pagination', () => {
    expect(
      assetSelectionQuery({
        q: ' %_ ',
        category: ' fixture ',
        locationMode: 'exact',
        location: ' Room %_1 ',
      }),
    ).toEqual({
      q: '%_',
      status: '',
      category: 'fixture',
      locationMode: 'exact',
      location: 'Room %_1',
      sort: 'updated_desc',
      warranty: null,
    });
  });
  it.each([
    { offset: '0' },
    { owner: 'other' },
    { q: ['a', 'b'] },
    { sort: {} },
    { location: 'Room' },
    { locationMode: 'exact' },
    { warranty: 'expired' },
    { asOf: '2026-10-29' },
    { warranty: 'expired', asOf: '2026-02-30' },
    { sort: 'unknown' },
  ])('rejects invalid query %j', (value) => {
    expect(() => assetSelectionQuery(value)).toThrow();
  });
  it('pins warranty reference instead of silently choosing today', () => {
    expect(
      assetSelectionQuery({ warranty: 'expiring_soon', asOf: '2026-10-29' })
        .warranty,
    ).toEqual({
      filter: 'expiring_soon',
      asOf: '2026-10-29',
      through: '2026-11-28',
    });
  });
  it('rejects anonymous and invalid queries before repository access', async () => {
    const repository = { exportSnapshot: jest.fn() };
    const controller = new AssetSelectionExportController(repository as never);
    await expect(controller.exportSelection({}, {})).rejects.toThrow();
    await expect(
      controller.exportSelection(
        { user: { userId: '507f1f77bcf86cd799439011' } },
        { offset: '0' },
      ),
    ).rejects.toThrow();
    expect(repository.exportSnapshot).not.toHaveBeenCalled();
  });
  it('passes only authenticated owner and validated filters', async () => {
    const repository = {
      exportSnapshot: jest
        .fn()
        .mockResolvedValue({ exportedAt: '2026-10-29T00:00:00Z', records: [] }),
    };
    const controller = new AssetSelectionExportController(repository as never);
    const result = await controller.exportSelection(
      { user: { userId: '507f1f77bcf86cd799439011' } },
      { q: '%_' },
    );
    expect(result.format).toBe('asset-desk-inventory-selection');
    expect(repository.exportSnapshot).toHaveBeenCalledWith(
      '507f1f77bcf86cd799439011',
      assetSelectionQuery({ q: '%_' }),
    );
  });
});
