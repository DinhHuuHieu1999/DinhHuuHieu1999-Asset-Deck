import { shouldExposeResetToken } from './auth-reset.util';

describe('shouldExposeResetToken', () => {
  it('is disabled by default outside production', () => {
    expect(shouldExposeResetToken('development')).toBe(false);
    expect(shouldExposeResetToken(undefined, undefined)).toBe(false);
  });

  it('requires an explicit true flag outside production', () => {
    expect(shouldExposeResetToken('development', 'true')).toBe(true);
    expect(shouldExposeResetToken('test', 'true')).toBe(true);
    expect(shouldExposeResetToken('development', 'TRUE')).toBe(false);
  });

  it('never exposes reset tokens in production', () => {
    expect(shouldExposeResetToken('production', 'true')).toBe(false);
  });
});
