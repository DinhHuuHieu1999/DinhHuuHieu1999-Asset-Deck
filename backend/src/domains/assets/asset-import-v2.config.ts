import { isAssetImportEnabled } from './asset-import.config';
import { isAssetDatesEnabled } from './asset-dates.config';

/** Enable only explicitly and only with the existing import/date prerequisites. */
export function isAssetImportV2Enabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_IMPORT_V2_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value !== 'true')
    throw new Error('ASSET_IMPORT_V2_ENABLED must be true or false');
  if (!isAssetImportEnabled(env) || !isAssetDatesEnabled(env))
    throw new Error(
      'ASSET_IMPORT_V2_ENABLED requires import and dates capabilities',
    );
  return true;
}
