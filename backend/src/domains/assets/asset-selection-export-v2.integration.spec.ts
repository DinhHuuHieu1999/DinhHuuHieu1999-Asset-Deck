import type { PostgresDatabase } from '../../infrastructure/database/postgres.database';
import { AssetSelectionExportV2Repository } from './asset-selection-export-v2.repository';
import {
  assetSelectionV2Query,
  AssetSelectionExportV2Controller,
} from './asset-selection-export-v2.controller';
import { isAssetSelectionExportV2Enabled } from './asset-selection-export-v2.config';

describe('selection v2 offline integration', () => {
  const query = jest.fn();
  const repository = new AssetSelectionExportV2Repository({
    pool: { query },
  } as unknown as PostgresDatabase);
  beforeEach(() => query.mockReset());
  it.each(['all', 'unknown', 'before', 'on_or_after'])(
    'binds owner and %s check scope in one statement',
    async (mode) => {
      const scope = assetSelectionV2Query({
        checkMode: mode,
        ...(['before', 'on_or_after'].includes(mode)
          ? { checkCutoff: '2024-02-29' }
          : {}),
      });
      query.mockResolvedValue({
        rows: [{ exportedAt: '2026-11-05T00:00:00Z', records: [] }],
      });
      await repository.exportSnapshot('507F1F77BCF86CD799439011', scope);
      expect(query).toHaveBeenCalledTimes(1);
      const [sql, values] = query.mock.calls[0];
      expect(values[0]).toBe('507f1f77bcf86cd799439011');
      expect(values[1]).toBe(501);
      expect(values.slice(10)).toEqual([
        mode,
        'cutoff' in scope.check ? scope.check.cutoff : null,
      ]);
      expect(sql).toContain('last_checked_on >= $12::date');
      expect(sql).toContain('AS "lastCheckedDate"');
      expect(sql).not.toContain('OFFSET');
    },
  );
  it.each([
    {},
    { checkMode: ['all'] },
    { checkMode: 'all', checkCutoff: '' },
    { checkMode: 'before', checkCutoff: '2023-02-29' },
    { checkMode: 'unknown', extra: 'x' },
    { checkMode: 'all', offset: '0' },
  ])('rejects invalid query %j', (value) => {
    expect(() => assetSelectionV2Query(value)).toThrow();
  });
  it('refuses invalid owner before SQL', async () => {
    await expect(
      repository.exportSnapshot(
        'bad',
        assetSelectionV2Query({ checkMode: 'all' }),
      ),
    ).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
  });
  it('controller rejects missing auth before repository access', async () => {
    await expect(
      new AssetSelectionExportV2Controller(repository).exportSelection(
        {},
        { checkMode: 'all' },
      ),
    ).rejects.toThrow();
    expect(query).not.toHaveBeenCalled();
  });
  it('defaults off and enforces prerequisites', () => {
    expect(isAssetSelectionExportV2Enabled({})).toBe(false);
    expect(() =>
      isAssetSelectionExportV2Enabled({
        ASSET_SELECTION_EXPORT_V2_ENABLED: 'TRUE',
      }),
    ).toThrow();
    expect(() =>
      isAssetSelectionExportV2Enabled({
        ASSET_SELECTION_EXPORT_V2_ENABLED: 'true',
      }),
    ).toThrow();
    expect(
      isAssetSelectionExportV2Enabled({
        ASSET_SELECTION_EXPORT_V2_ENABLED: 'true',
        ASSET_SELECTION_EXPORT_ENABLED: 'true',
        ASSET_DATES_ENABLED: 'true',
        ASSET_LOCATION_ENABLED: 'true',
        ASSET_CHECK_ENABLED: 'true',
      }),
    ).toBe(true);
  });
});
