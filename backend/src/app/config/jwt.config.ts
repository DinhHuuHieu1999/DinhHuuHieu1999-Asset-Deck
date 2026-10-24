const DEVELOPMENT_JWT_SECRET = ['dev', 'insecure', 'change', 'me'].join('-');
const MINIMUM_PRODUCTION_SECRET_LENGTH = 32;

/**
 * Resolves the JWT signing secret while preventing a known development fallback
 * from being used in production.
 */
export function resolveJwtAccessSecret(
  secret: string | undefined,
  nodeEnv: string | undefined,
) {
  const configuredSecret = secret?.trim();
  if (nodeEnv === 'production') {
    if (
      !configuredSecret ||
      configuredSecret.length < MINIMUM_PRODUCTION_SECRET_LENGTH
    ) {
      throw new Error(
        `JWT_ACCESS_SECRET must contain at least ${MINIMUM_PRODUCTION_SECRET_LENGTH} characters in production`,
      );
    }
    return configuredSecret;
  }

  return configuredSecret || DEVELOPMENT_JWT_SECRET;
}
