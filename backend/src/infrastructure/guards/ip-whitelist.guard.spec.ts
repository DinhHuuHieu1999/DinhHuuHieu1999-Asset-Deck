import { ForbiddenException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import express from 'express';
import type { Request } from 'express';
import request from 'supertest';
import { IpWhitelistGuard } from './ip-whitelist.guard';

describe('IpWhitelistGuard proxy boundary', () => {
  const originalWhitelist = process.env.IP_WHITELIST;

  afterEach(() => {
    if (originalWhitelist === undefined) delete process.env.IP_WHITELIST;
    else process.env.IP_WHITELIST = originalWhitelist;
  });

  function createGuard(isPublic = false): IpWhitelistGuard {
    const reflector = {
      getAllAndOverride: () => isPublic,
    } as unknown as Reflector;
    return new IpWhitelistGuard(reflector);
  }

  function context(req: Request): ExecutionContext {
    return {
      getHandler: () => undefined,
      getClass: () => undefined,
      switchToHttp: () => ({ getRequest: () => req }),
    } as unknown as ExecutionContext;
  }

  it('rejects a forged allowlisted forwarded header from an untrusted peer', async () => {
    process.env.IP_WHITELIST = '203.0.113.10';
    const guard = createGuard();
    const app = express();
    app.set('trust proxy', false);
    app.get('/', (req, res) => {
      try {
        guard.canActivate(context(req));
        res.sendStatus(200);
      } catch (error) {
        expect(error).toBeInstanceOf(ForbiddenException);
        res.sendStatus(403);
      }
    });
    await request(app)
      .get('/')
      .set('X-Forwarded-For', '203.0.113.10')
      .expect(403);
  });

  it('uses the nearest untrusted address, not the first forwarded entry', async () => {
    process.env.IP_WHITELIST = '203.0.113.10';
    const guard = createGuard();
    const app = express();
    app.set('trust proxy', 'loopback');
    app.get('/', (req, res) => {
      try {
        guard.canActivate(context(req));
        res.sendStatus(200);
      } catch {
        res.sendStatus(403);
      }
    });
    await request(app)
      .get('/')
      .set('X-Forwarded-For', '203.0.113.10')
      .expect(200);
    await request(app)
      .get('/')
      .set('X-Forwarded-For', '203.0.113.10, 198.51.100.20')
      .expect(403);
  });

  it('normalizes IPv4-mapped addresses', () => {
    process.env.IP_WHITELIST = '203.0.113.10';
    expect(
      createGuard().canActivate(
        context({ ip: '::ffff:203.0.113.10' } as Request),
      ),
    ).toBe(true);
  });

  it('denies requests without a resolved IP when a whitelist is configured', () => {
    process.env.IP_WHITELIST = '203.0.113.10';
    expect(() => createGuard().canActivate(context({} as Request))).toThrow(
      ForbiddenException,
    );
  });

  it('preserves public routes and an empty whitelist', () => {
    process.env.IP_WHITELIST = '203.0.113.10';
    expect(createGuard(true).canActivate(context({} as Request))).toBe(true);
    process.env.IP_WHITELIST = '';
    expect(createGuard().canActivate(context({} as Request))).toBe(true);
  });
});
