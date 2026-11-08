import { isAssetDatesEnabled } from './asset-dates.config';
import { isAssetLocationEnabled } from './asset-location.config';

/** V3 export is explicit and requires date/location capabilities. */
export function isAssetExportV3Enabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_EXPORT_V3_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value !== 'true')
    throw new Error('ASSET_EXPORT_V3_ENABLED must be true or false');
  if (!isAssetDatesEnabled(env) || !isAssetLocationEnabled(env)) {
    throw new Error('ASSET_EXPORT_V3_ENABLED requires dates and location');
  }
  return true;
}
