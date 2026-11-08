/** Explicit opt-in; malformed values never enable the date capability. */
export function isAssetDatesEnabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_DATES_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error('ASSET_DATES_ENABLED must be true or false');
}
