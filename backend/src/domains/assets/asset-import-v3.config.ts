import { isAssetImportEnabled } from './asset-import.config';
import { isAssetLocationEnabled } from './asset-location.config';
import { isAssetDatesEnabled } from './asset-dates.config';

/** Enable only explicitly and only with the existing import/date prerequisites. */
export function isAssetImportV3Enabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_IMPORT_V3_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value !== 'true')
    throw new Error('ASSET_IMPORT_V3_ENABLED must be true or false');
  if (
    !isAssetImportEnabled(env) ||
    !isAssetDatesEnabled(env) ||
    !isAssetLocationEnabled(env)
  )
    throw new Error(
      'ASSET_IMPORT_V3_ENABLED requires import, dates and location capabilities',
    );
  return true;
}
