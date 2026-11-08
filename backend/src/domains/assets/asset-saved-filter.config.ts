/** Explicit opt-in only; ambiguous configuration refuses startup. */
export function isAssetSavedFilterEnabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_SAVED_FILTERS_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error('ASSET_SAVED_FILTERS_ENABLED must be true or false');
}
