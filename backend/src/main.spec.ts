import { validateStartup } from './app/config/startup.config';

describe('Asset Desk startup contract', () => {
  const original = { ...process.env };
  beforeEach(() => {
    process.env.JWT_ACCESS_SECRET =
      'synthetic-jwt-secret-with-at-least-32-characters';
    process.env.CSRF_ENABLED = 'true';
    process.env.CSRF_SECRET =
      'synthetic-csrf-secret-with-at-least-32-characters';
    delete process.env.BACKEND_HTTP_PORT;
    delete process.env.AUTH_EXPOSE_RESET_TOKEN;
  });
  afterEach(() => {
    process.env = { ...original };
  });

  it('accepts explicit security settings without starting a listener', () => {
    expect(validateStartup()).toBe(8180);
    process.env.BACKEND_HTTP_PORT = '8181';
    expect(validateStartup()).toBe(8181);
  });
  it.each(['0', '-1', '65536', '1.5', '8180extra', ''])(
    'rejects invalid port %j',
    (value) => {
      process.env.BACKEND_HTTP_PORT = value;
      expect(validateStartup).toThrow('BACKEND_HTTP_PORT');
    },
  );
  it.each(['false', '', 'TRUE'])(
    'requires explicit CSRF protection %j',
    (value) => {
      process.env.CSRF_ENABLED = value;
      expect(validateStartup).toThrow('CSRF');
    },
  );
  it('rejects missing secrets and reset-token exposure', () => {
    process.env.JWT_ACCESS_SECRET = '';
    expect(validateStartup).toThrow('JWT');
    process.env.JWT_ACCESS_SECRET = 'synthetic-long-jwt-secret-32-characters';
    process.env.CSRF_SECRET = '';
    expect(validateStartup).toThrow('CSRF');
    process.env.CSRF_SECRET = 'synthetic-long-csrf-secret-32-characters';
    process.env.AUTH_EXPOSE_RESET_TOKEN = 'true';
    expect(validateStartup).toThrow('Reset token exposure');
  });
});
