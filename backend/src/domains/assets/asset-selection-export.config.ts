import { isAssetDatesEnabled } from './asset-dates.config';
import { isAssetLocationEnabled } from './asset-location.config';

/** Selection export is explicit and requires date/location capabilities. */
export function isAssetSelectionExportEnabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_SELECTION_EXPORT_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value !== 'true')
    throw new Error('ASSET_SELECTION_EXPORT_ENABLED must be true or false');
  if (!isAssetDatesEnabled(env) || !isAssetLocationEnabled(env)) {
    throw new Error(
      'ASSET_SELECTION_EXPORT_ENABLED requires dates and location',
    );
  }
  return true;
}
