import { isAssetCheckEnabled } from './asset-check';
import { isAssetDatesEnabled } from './asset-dates.config';
import { isAssetLocationEnabled } from './asset-location.config';

/** V4 export is explicit and requires date/location capabilities. */
export function isAssetExportV4Enabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_EXPORT_V4_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value !== 'true')
    throw new Error('ASSET_EXPORT_V4_ENABLED must be true or false');
  if (
    !isAssetDatesEnabled(env) ||
    !isAssetLocationEnabled(env) ||
    !isAssetCheckEnabled(env)
  ) {
    throw new Error(
      'ASSET_EXPORT_V4_ENABLED requires dates, location and manual check',
    );
  }
  return true;
}
