import { CsrfService } from './csrf.service';

describe('CsrfService', () => {
  const originalEnv = process.env;

  afterEach(() => {
    process.env = originalEnv;
  });

  it('rejects an unsafe production configuration', () => {
    process.env = {
      ...originalEnv,
      NODE_ENV: 'production',
      CSRF_ENABLED: 'true',
      CSRF_SECRET: 'short',
    };

    expect(() => new CsrfService()).toThrow(
      'CSRF_SECRET must contain at least 32 characters',
    );
  });

  it('can remain disabled without a configured secret', () => {
    process.env = {
      ...originalEnv,
      NODE_ENV: 'production',
      CSRF_ENABLED: 'false',
      CSRF_SECRET: '',
    };

    const service = new CsrfService();
    const next = jest.fn();
    service.doubleCsrfProtection({} as never, {} as never, next);

    expect(next).toHaveBeenCalledTimes(1);
  });

  it('rejects an unsafe request without the double-submit token when enabled', () => {
    process.env = {
      ...originalEnv,
      NODE_ENV: 'test',
      CSRF_ENABLED: 'true',
      CSRF_SECRET: 'test-secret-with-at-least-32-characters',
    };

    const service = new CsrfService();
    const next = jest.fn();
    service.doubleCsrfProtection(
      { method: 'POST', headers: {}, cookies: {} } as never,
      {} as never,
      next,
    );

    expect(next).toHaveBeenCalledWith(expect.any(Error));
  });
});
