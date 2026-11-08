// Adapted from the ToolDeck opt-in import source contract.
import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { UnauthorizedException, type ExecutionContext } from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import type { Request, Response } from 'express';
import { JwtAuthGuard } from '../../infrastructure/guards/jwt-auth.guard';
import { CsrfService } from '../../app/services/csrf.service';
import { AssetImportController } from './asset-import.controller';
import { AssetImportRepository } from './asset-import.repository';
import { ASSET_IMPORT_MAX_BYTES } from './asset-import';
import { createAssetImportParser } from './asset-import-parser';

const owner = '0123456789abcdef01234567';
const other = '1123456789abcdef01234567';
const input = {
  requestId: '7971aec3-ed1b-4ed0-9de5-e9ad617d752e',
  records: [
    {
      name: 'Synthetic',
      serial: '%_1',
      category: 'test',
      status: 'stored',
      notes: '',
    },
  ],
};

describe('Import candidate HTTP contract (no SQL; synthetic auth)', () => {
  let app: NestExpressApplication;
  const originalEnv = process.env;
  const pool = { connect: jest.fn() };
  const repository = new AssetImportRepository({ pool } as never);
  let csrf: CsrfService;
  beforeAll(async () => {
    process.env = {
      ...originalEnv,
      NODE_ENV: 'test',
      CSRF_ENABLED: 'true',
      CSRF_SECRET: 'synthetic-only-csrf-secret-32-characters',
      CSRF_COOKIE_NAME: 'import_fixture_csrf',
      CSRF_COOKIE_SECURE: 'false',
      CSRF_COOKIE_SAME_SITE: 'lax',
    };
    csrf = new CsrfService();
    const module = await Test.createTestingModule({
      controllers: [AssetImportController],
      providers: [{ provide: AssetImportRepository, useValue: repository }],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate(context: ExecutionContext) {
          const req = context
            .switchToHttp()
            .getRequest<Request & { user?: { userId: string } }>();
          const token = req.headers.authorization;
          if (token !== 'Bearer synthetic' && token !== 'Bearer other')
            throw new UnauthorizedException();
          req.user = { userId: token === 'Bearer other' ? other : owner };
          return true;
        },
      })
      .compile();
    app = module.createNestApplication<NestExpressApplication>({
      logger: false,
    });
    app.setGlobalPrefix('api/v1');
    app.use(createAssetImportParser());
    app.use(cookieParser());
    app.use(csrf.doubleCsrfProtection);
    app.use('/synthetic-csrf', (req: Request, res: Response) => {
      res.json({ token: csrf.generateCsrfToken(req, res) });
    });
    await app.init();
  });
  afterAll(async () => {
    await app?.close();
    process.env = originalEnv;
  });
  beforeEach(() => {
    jest.clearAllMocks();
  });

  async function credentials() {
    const response = await request(app.getHttpServer())
      .get('/synthetic-csrf')
      .expect(200);
    return {
      token: (response.body as { token: string }).token,
      cookies: response.headers['set-cookie'] as unknown as string[],
    };
  }

  it('rejects missing/invalid CSRF before any connection', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/assets/import')
      .auth('synthetic', { type: 'bearer' })
      .send(input)
      .expect(403);
    const auth = await credentials();
    await request(app.getHttpServer())
      .post('/api/v1/assets/import')
      .auth('synthetic', { type: 'bearer' })
      .set('Cookie', auth.cookies)
      .set('x-csrf-token', 'invalid')
      .send(input)
      .expect(403);
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it('rejects unauthenticated requests even with a valid CSRF token', async () => {
    const auth = await credentials();
    await request(app.getHttpServer())
      .post('/api/v1/assets/import')
      .set('Cookie', auth.cookies)
      .set('x-csrf-token', auth.token)
      .send(input)
      .expect(401);
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it.each([
    { ...input, owner: other },
    { ...input, records: [{ ...input.records[0], id: input.requestId }] },
    { ...input, records: [] },
  ])('rejects invalid batch %# before any SQL', async (value) => {
    const auth = await credentials();
    await request(app.getHttpServer())
      .post('/api/v1/assets/import')
      .auth('synthetic', { type: 'bearer' })
      .set('Cookie', auth.cookies)
      .set('x-csrf-token', auth.token)
      .send(value)
      .expect(400);
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it('rejects query options rather than allowing owner override', async () => {
    const auth = await credentials();
    await request(app.getHttpServer())
      .post('/api/v1/assets/import?owner=other')
      .auth('synthetic', { type: 'bearer' })
      .set('Cookie', auth.cookies)
      .set('x-csrf-token', auth.token)
      .send(input)
      .expect(400);
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it('enforces raw request bytes before acquiring a connection', async () => {
    const auth = await credentials();
    await request(app.getHttpServer())
      .post('/api/v1/assets/import')
      .auth('synthetic', { type: 'bearer' })
      .set('Cookie', auth.cookies)
      .set('x-csrf-token', auth.token)
      .send({ ...input, padding: 'x'.repeat(ASSET_IMPORT_MAX_BYTES) })
      .expect(413);
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it('accepts a valid batch larger than 100 KiB in the isolated parser configuration', async () => {
    const auth = await credentials();
    const records = Array.from({ length: 60 }, () => ({
      ...input.records[0],
      notes: 'x'.repeat(2000),
    }));
    const client = {
      query: jest
        .fn()
        .mockResolvedValue({ rows: [], rowCount: records.length }),
      release: jest.fn(),
    };
    client.query
      .mockResolvedValueOnce({ rows: [], rowCount: 0 })
      .mockResolvedValueOnce({
        rows: [{ request_id: input.requestId }],
        rowCount: 1,
      });
    pool.connect.mockResolvedValueOnce(client);
    const response = await request(app.getHttpServer())
      .post('/api/v1/assets/import')
      .auth('synthetic', { type: 'bearer' })
      .set('Cookie', auth.cookies)
      .set('x-csrf-token', auth.token)
      .send({ ...input, records })
      .expect(200);
    expect(response.body).toMatchObject({ recordCount: 60 });
    expect(client.query).toHaveBeenCalledTimes(4);
  });

  it.each(['synthetic', 'other'])(
    'uses the authenticated %s owner and no-store response',
    async (token) => {
      const auth = await credentials();
      const client = {
        query: jest.fn().mockResolvedValue({ rows: [], rowCount: 1 }),
        release: jest.fn(),
      };
      client.query
        .mockResolvedValueOnce({ rows: [], rowCount: 0 })
        .mockResolvedValueOnce({
          rows: [{ request_id: input.requestId }],
          rowCount: 1,
        });
      pool.connect.mockResolvedValueOnce(client);
      const response = await request(app.getHttpServer())
        .post('/api/v1/assets/import')
        .auth(token, { type: 'bearer' })
        .set('Cookie', auth.cookies)
        .set('x-csrf-token', auth.token)
        .send(input)
        .expect(200);
      expect(response.headers['cache-control']).toBe('no-store');
      expect(response.body).toMatchObject({
        requestId: input.requestId,
        recordCount: 1,
      });
      expect(client.query.mock.calls[1][1][0]).toBe(
        token === 'other' ? other : owner,
      );
    },
  );
});
