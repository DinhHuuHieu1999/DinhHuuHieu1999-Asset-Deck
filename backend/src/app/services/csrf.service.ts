import { Injectable } from '@nestjs/common';
import { doubleCsrf } from 'csrf-csrf';
import type { DoubleCsrfConfigOptions } from 'csrf-csrf';
import type { NextFunction, Request, Response } from 'express';

@Injectable()
export class CsrfService {
  public readonly generateCsrfToken: (req: Request, res: Response) => string;
  public readonly doubleCsrfProtection: (
    req: Request,
    res: Response,
    next: NextFunction,
  ) => void;

  constructor() {
    const isEnabled = process.env.CSRF_ENABLED === 'true';
    const configuredSecret = process.env.CSRF_SECRET?.trim();
    if (
      isEnabled &&
      process.env.NODE_ENV === 'production' &&
      (!configuredSecret || configuredSecret.length < 32)
    ) {
      throw new Error(
        'CSRF_SECRET must contain at least 32 characters when CSRF is enabled in production',
      );
    }
    const getSecret = (): string =>
      configuredSecret || 'development-only-csrf-secret-change-me';
    const getSessionIdentifier = (): string => 'global';

    if (isEnabled) {
      const config: DoubleCsrfConfigOptions = {
        getSecret,
        getSessionIdentifier,
        getCsrfTokenFromRequest: (req: Request) =>
          req.headers['x-csrf-token'] || '',
        cookieName: process.env.CSRF_COOKIE_NAME || 'csrf_token',
        cookieOptions: {
          httpOnly: process.env.CSRF_COOKIE_HTTP_ONLY !== 'false',
          sameSite: (process.env.CSRF_COOKIE_SAME_SITE || 'lax') as
            'lax' | 'strict' | 'none',
          secure: process.env.CSRF_COOKIE_SECURE === 'true',
          path: '/',
        },
      };

      const { generateCsrfToken, doubleCsrfProtection } = doubleCsrf(config);
      this.generateCsrfToken = generateCsrfToken;
      this.doubleCsrfProtection = doubleCsrfProtection;
    } else {
      this.generateCsrfToken = () => '';
      this.doubleCsrfProtection = (
        _req: Request,
        _res: Response,
        next: NextFunction,
      ) => {
        next();
      };
    }
  }
}
