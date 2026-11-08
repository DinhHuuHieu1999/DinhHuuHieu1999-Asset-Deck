/** Explicit opt-in only; malformed values fail closed without enabling writes. */
export function isAssetImportEnabled(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.ASSET_IMPORT_ENABLED;
  if (value === undefined || value === 'false') return false;
  if (value === 'true') return true;
  throw new Error('ASSET_IMPORT_ENABLED must be true or false');
}
