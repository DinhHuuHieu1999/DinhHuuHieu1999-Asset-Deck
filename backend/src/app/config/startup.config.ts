import { resolveJwtAccessSecret } from './jwt.config';

/** Validate required security settings before opening storage or network listeners. */
export function validateStartup(): number {
  resolveJwtAccessSecret(process.env.JWT_ACCESS_SECRET, 'production');
  if (
    process.env.CSRF_ENABLED !== 'true' ||
    !process.env.CSRF_SECRET ||
    process.env.CSRF_SECRET.trim().length < 32
  ) {
    throw new Error(
      'Enable CSRF and configure a secret of at least 32 characters',
    );
  }
  if (process.env.AUTH_EXPOSE_RESET_TOKEN === 'true') {
    throw new Error('Reset token exposure is not supported by Asset Desk');
  }
  const raw = process.env.BACKEND_HTTP_PORT ?? '8180';
  if (!/^\d+$/.test(raw) || Number(raw) < 1 || Number(raw) > 65535) {
    throw new Error('BACKEND_HTTP_PORT must be an integer from 1 to 65535');
  }
  return Number(raw);
}
