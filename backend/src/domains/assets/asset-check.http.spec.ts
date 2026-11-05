import { AssetsController } from './assets.controller';
import { AssetsService } from './assets.service';
import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import {
  UnauthorizedException,
  ValidationPipe,
  type ExecutionContext,
} from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import cookieParser from 'cookie-parser';
import request from 'supertest';
import type { Request, Response } from 'express';
import { JwtAuthGuard } from '../../infrastructure/guards/jwt-auth.guard';
import { CsrfService } from '../../app/services/csrf.service';
import { AssetCheckController } from './asset-check.controller';
import { AssetCheckRepository } from './asset-check.repository';
const owner = '507f1f77bcf86cd799439011';
const id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
describe('Check date HTTP validation with synthetic auth and no SQL', () => {
  let app: NestExpressApplication;
  const originalEnv = process.env;
  const repository = {
    overview: jest.fn(),
    read: jest.fn(),
    update: jest.fn(),
    list: jest.fn(),
  };
  beforeAll(async () => {
    process.env = {
      ...originalEnv,
      NODE_ENV: 'test',
      CSRF_ENABLED: 'true',
      CSRF_SECRET: 'synthetic-only-csrf-secret-32-characters',
      CSRF_COOKIE_NAME: 'location_fixture_csrf',
      CSRF_COOKIE_SECURE: 'false',
      CSRF_COOKIE_SAME_SITE: 'lax',
    };
    const csrf = new CsrfService();
    const module = await Test.createTestingModule({
      controllers: [AssetsController, AssetCheckController],
      providers: [
        { provide: AssetCheckRepository, useValue: repository },
        { provide: AssetsService, useValue: {} },
      ],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate(context: ExecutionContext) {
          const req = context
            .switchToHttp()
            .getRequest<Request & { user?: { userId: string } }>();
          if (req.headers.authorization !== 'Bearer synthetic')
            throw new UnauthorizedException();
          req.user = { userId: owner };
          return true;
        },
      })
      .compile();
    app = module.createNestApplication<NestExpressApplication>({
      logger: false,
    });
    app.setGlobalPrefix('api/v1');
    app.useGlobalPipes(
      new ValidationPipe({
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
      }),
    );
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
  beforeEach(() => jest.resetAllMocks());

  it('rejects anonymous reads and CSRF-free writes before persistence', async () => {
    await request(app.getHttpServer())
      .get(`/api/v1/assets/${id}/check-date`)
      .expect(401);
    await request(app.getHttpServer())
      .put(`/api/v1/assets/${id}/check-date`)
      .auth('synthetic', { type: 'bearer' })
      .send({ version: 1, lastCheckedOn: null })
      .expect(403);
    expect(repository.read).not.toHaveBeenCalled();
    expect(repository.update).not.toHaveBeenCalled();
  });
  it('validates UUID/query and returns owner-bound no-store snapshot', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/bad/check-date')
      .auth('synthetic', { type: 'bearer' })
      .expect(400);
    await request(app.getHttpServer())
      .get(`/api/v1/assets/${id}/check-date?owner=other`)
      .auth('synthetic', { type: 'bearer' })
      .expect(400);
    expect(repository.read).not.toHaveBeenCalled();
    const row = { id, version: 1, lastCheckedOn: null };
    repository.read.mockResolvedValue(row);
    const response = await request(app.getHttpServer())
      .get(`/api/v1/assets/${id}/check-date`)
      .auth('synthetic', { type: 'bearer' })
      .expect(200);
    expect(response.body).toEqual(row);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(repository.read).toHaveBeenCalledWith(owner, id);
  });
  it('valid CSRF does not permit extra fields or future dates; clear is explicit', async () => {
    const credentials = await request(app.getHttpServer())
      .get('/synthetic-csrf')
      .expect(200);
    const put = (body: unknown) =>
      request(app.getHttpServer())
        .put(`/api/v1/assets/${id}/check-date`)
        .auth('synthetic', { type: 'bearer' })
        .set('Cookie', credentials.headers['set-cookie'])
        .set('x-csrf-token', (credentials.body as { token: string }).token)
        .send(body as object);
    await put({ version: 1, lastCheckedOn: null, owner: 'other' }).expect(400);
    await put({ version: 1, lastCheckedOn: '9999-12-31' }).expect(400);
    expect(repository.update).not.toHaveBeenCalled();
    repository.update.mockResolvedValue({
      id,
      version: 2,
      lastCheckedOn: null,
    });
    const result = await put({ version: 1, lastCheckedOn: null }).expect(200);
    expect(result.headers['cache-control']).toBe('no-store');
    expect(repository.update).toHaveBeenCalledWith(owner, id, {
      version: 1,
      lastCheckedOn: null,
    });
  });
  it('overview is authenticated, no-store and passes only an explicit cutoff', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/check-overview/counts?cutoff=2024-02-29')
      .expect(401);
    expect(repository.overview).not.toHaveBeenCalled();
    for (const suffix of [
      '',
      '?cutoff=2023-02-29',
      '?cutoff=2024-02-29&owner=other',
      '?cutoff=2024-02-29&cutoff=2024-03-01',
    ]) {
      await request(app.getHttpServer())
        .get('/api/v1/assets/check-overview/counts' + suffix)
        .auth('synthetic', { type: 'bearer' })
        .expect(400);
    }
    expect(repository.overview).not.toHaveBeenCalled();
    const row = {
      complete: true,
      cutoff: '2024-02-29',
      total: 0,
      unknown: 0,
      before: 0,
      onOrAfter: 0,
    };
    repository.overview.mockResolvedValue(row);
    const response = await request(app.getHttpServer())
      .get('/api/v1/assets/check-overview/counts?cutoff=2024-02-29')
      .auth('synthetic', { type: 'bearer' })
      .expect(200);
    expect(response.body).toEqual(row);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(repository.overview).toHaveBeenCalledWith(owner, '2024-02-29');
  });
});
