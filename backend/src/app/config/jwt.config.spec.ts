import { resolveJwtAccessSecret } from './jwt.config';

describe('resolveJwtAccessSecret', () => {
  it('uses the development fallback outside production', () => {
    expect(resolveJwtAccessSecret(undefined, 'development')).toBe(
      'dev-insecure-change-me',
    );
  });

  it('returns a configured secret after trimming it', () => {
    expect(resolveJwtAccessSecret('  local-secret  ', 'development')).toBe(
      'local-secret',
    );
  });

  it('rejects a missing production secret', () => {
    expect(() => resolveJwtAccessSecret(undefined, 'production')).toThrow(
      'JWT_ACCESS_SECRET must contain at least 32 characters in production',
    );
  });

  it('rejects a short production secret', () => {
    expect(() => resolveJwtAccessSecret('too-short', 'production')).toThrow(
      'JWT_ACCESS_SECRET must contain at least 32 characters in production',
    );
  });

  it('accepts a sufficiently long production secret', () => {
    const secret = ['production', 'secret', 'for', 'validation', 'only'].join(
      '-',
    );
    expect(resolveJwtAccessSecret(secret, 'production')).toBe(secret);
  });
});
