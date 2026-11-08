import { isAssetSelectionExportEnabled } from './asset-selection-export.config';
import { isAssetCheckEnabled } from './asset-check';

/** Keep v2 opt-in and require every schema capability it reads. */
export function isAssetSelectionExportV2Enabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_SELECTION_EXPORT_V2_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value !== 'true')
    throw new Error('ASSET_SELECTION_EXPORT_V2_ENABLED must be true or false');
  if (!isAssetSelectionExportEnabled(env) || !isAssetCheckEnabled(env))
    throw new Error(
      'ASSET_SELECTION_EXPORT_V2_ENABLED requires selection export and asset check',
    );
  return true;
}
