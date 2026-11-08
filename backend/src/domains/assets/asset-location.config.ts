/** Location access is opt-in; invalid configuration refuses startup. */
export function isAssetLocationEnabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_LOCATION_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error('ASSET_LOCATION_ENABLED must be true or false');
}
