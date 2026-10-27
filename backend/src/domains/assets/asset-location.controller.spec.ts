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
jest.mock('../auth/auth.module', () => ({ AuthModule: class AuthModule {} }));
import {
  AssetLocationController,
  AssetLocationQueryDto,
} from './asset-location.controller';
import { AssetLocationRepository } from './asset-location.repository';
import { isAssetLocationEnabled } from './asset-location.config';
import { AssetLocationModule } from './asset-location.module';

const owner = '507f1f77bcf86cd799439011';
const id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
describe('location controller boundary', () => {
  const repository = {
    read: jest.fn(),
    update: jest.fn(),
    list: jest.fn(),
    ready: jest.fn(),
  };
  const controller = new AssetLocationController(
    repository as unknown as AssetLocationRepository,
  );
  const originalDates = process.env.ASSET_DATES_ENABLED;
  beforeEach(() => {
    jest.resetAllMocks();
    delete process.env.ASSET_DATES_ENABLED;
  });
  afterEach(() => {
    if (originalDates === undefined) delete process.env.ASSET_DATES_ENABLED;
    else process.env.ASSET_DATES_ENABLED = originalDates;
  });
  it('requires an authenticated valid owner before persistence', async () => {
    await expect(controller.read({}, id, {})).rejects.toThrow('Unauthorized');
    expect(repository.read).not.toHaveBeenCalled();
  });
  it('does not reveal missing or other-owner asset on read/update', async () => {
    await expect(
      controller.read({ user: { userId: owner } }, id, {}),
    ).rejects.toThrow('unavailable');
    await expect(
      controller.update(
        { user: { userId: owner } },
        id,
        { version: 1, location: null },
        {},
      ),
    ).rejects.toThrow('changed or is unavailable');
  });
  it('rejects query owner injection and unknown update fields', async () => {
    await expect(
      controller.read({ user: { userId: owner } }, id, { owner }),
    ).rejects.toThrow('query');
    await expect(
      controller.update(
        { user: { userId: owner } },
        id,
        { version: 1, location: 'A', owner },
        {},
      ),
    ).rejects.toThrow('Invalid');
    expect(repository.read).not.toHaveBeenCalled();
    expect(repository.update).not.toHaveBeenCalled();
  });
  it('requires a label only in exact mode', async () => {
    await expect(
      controller.list(
        { user: { userId: owner } },
        Object.assign(new AssetLocationQueryDto(), { location: 'A' }),
      ),
    ).rejects.toThrow('exact');
    await expect(
      controller.list(
        { user: { userId: owner } },
        Object.assign(new AssetLocationQueryDto(), { locationMode: 'exact' }),
      ),
    ).rejects.toThrow('Invalid');
    expect(repository.list).not.toHaveBeenCalled();
  });
  it('passes normalized exact location and authenticated owner', async () => {
    const query = Object.assign(new AssetLocationQueryDto(), {
      locationMode: 'exact',
      location: ' Room A ',
    });
    await controller.list({ user: { userId: owner } }, query);
    expect(repository.list).toHaveBeenCalledWith(
      owner,
      query,
      {
        mode: 'exact',
        location: 'Room A',
      },
      undefined,
    );
  });
  it('defaults off and refuses ambiguous config', () => {
    expect(isAssetLocationEnabled({})).toBe(false);
    expect(isAssetLocationEnabled({ ASSET_LOCATION_ENABLED: 'false' })).toBe(
      false,
    );
    expect(isAssetLocationEnabled({ ASSET_LOCATION_ENABLED: 'true' })).toBe(
      true,
    );
    for (const value of ['TRUE', '1', '', ' true '])
      expect(() =>
        isAssetLocationEnabled({ ASSET_LOCATION_ENABLED: value }),
      ).toThrow();
  });
  it('enabled module propagates missing schema without applying migration', async () => {
    repository.ready.mockRejectedValue(new Error('missing schema'));
    const module = new AssetLocationModule(
      repository as unknown as AssetLocationRepository,
    );
    await expect(module.onModuleInit()).rejects.toThrow('missing schema');
    expect(repository.ready).toHaveBeenCalledTimes(1);
  });
  it('refuses warranty when dates are disabled and refuses orphan reference dates', async () => {
    const request = { user: { userId: owner } };
    await expect(
      controller.list(
        request,
        Object.assign(new AssetLocationQueryDto(), { warranty: 'expired' }),
      ),
    ).rejects.toThrow('unavailable');
    await expect(
      controller.list(
        request,
        Object.assign(new AssetLocationQueryDto(), { asOf: '2026-10-27' }),
      ),
    ).rejects.toThrow('requires warranty');
    expect(repository.list).not.toHaveBeenCalled();
  });
  it('validates enabled warranty calendars and passes the resolved window', async () => {
    process.env.ASSET_DATES_ENABLED = 'true';
    const request = { user: { userId: owner } };
    await expect(
      controller.list(
        request,
        Object.assign(new AssetLocationQueryDto(), {
          warranty: 'expired',
          asOf: '2026-02-30',
        }),
      ),
    ).rejects.toThrow('Invalid');
    const query = Object.assign(new AssetLocationQueryDto(), {
      warranty: 'expiring_soon',
      asOf: '2026-10-27',
    });
    await controller.list(request, query);
    expect(repository.list).toHaveBeenCalledWith(
      owner,
      query,
      { mode: 'all', location: null },
      { filter: 'expiring_soon', asOf: '2026-10-27', through: '2026-11-26' },
    );
  });
});

describe('Location HTTP validation with synthetic auth and no SQL', () => {
  let app: NestExpressApplication;
  const originalEnv = process.env;
  const repository = { read: jest.fn(), update: jest.fn(), list: jest.fn() };
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
      controllers: [AssetLocationController],
      providers: [{ provide: AssetLocationRepository, useValue: repository }],
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

  it('rejects unauthenticated reads and missing CSRF writes before persistence', async () => {
    await request(app.getHttpServer())
      .get(`/api/v1/assets/${id}/location`)
      .expect(401);
    await request(app.getHttpServer())
      .put(`/api/v1/assets/${id}/location`)
      .auth('synthetic', { type: 'bearer' })
      .send({ version: 1, location: 'Office' })
      .expect(403);
    expect(repository.read).not.toHaveBeenCalled();
    expect(repository.update).not.toHaveBeenCalled();
  });

  it.each([
    'owner=other',
    'locationMode=invalid',
    'locationMode=exact&location=A&location=B',
    'offset=-1',
  ])('rejects invalid list query %s before persistence', async (query) => {
    await request(app.getHttpServer())
      .get(`/api/v1/assets/locations/inventory?${query}`)
      .auth('synthetic', { type: 'bearer' })
      .expect(400);
    expect(repository.list).not.toHaveBeenCalled();
  });

  it('routes the literal filter through the validated DTO and applies no-store', async () => {
    repository.list.mockResolvedValue({ items: [], nextOffset: null });
    const result = await request(app.getHttpServer())
      .get('/api/v1/assets/locations/inventory')
      .query({ locationMode: 'exact', location: '%_Room' })
      .auth('synthetic', { type: 'bearer' })
      .expect(200);
    expect(result.headers['cache-control']).toBe('no-store');
    expect(repository.list).toHaveBeenCalledWith(
      owner,
      expect.any(AssetLocationQueryDto),
      { mode: 'exact', location: '%_Room' },
      undefined,
    );
  });

  it('requires UUIDs and rejects update owner injection even with valid CSRF', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/not-a-uuid/location')
      .auth('synthetic', { type: 'bearer' })
      .expect(400);
    const credentials = await request(app.getHttpServer())
      .get('/synthetic-csrf')
      .expect(200);
    await request(app.getHttpServer())
      .put(`/api/v1/assets/${id}/location`)
      .auth('synthetic', { type: 'bearer' })
      .set('Cookie', credentials.headers['set-cookie'])
      .set('x-csrf-token', (credentials.body as { token: string }).token)
      .send({ version: 1, location: 'Office', owner: 'other' })
      .expect(400);
    expect(repository.read).not.toHaveBeenCalled();
    expect(repository.update).not.toHaveBeenCalled();
  });

  it('normalizes an explicit authenticated write without changing its version', async () => {
    repository.update.mockResolvedValue({ id, version: 2, location: 'Office' });
    const credentials = await request(app.getHttpServer())
      .get('/synthetic-csrf')
      .expect(200);
    await request(app.getHttpServer())
      .put(`/api/v1/assets/${id}/location`)
      .auth('synthetic', { type: 'bearer' })
      .set('Cookie', credentials.headers['set-cookie'])
      .set('x-csrf-token', (credentials.body as { token: string }).token)
      .send({ version: 1, location: ' Office ' })
      .expect(200);
    expect(repository.update).toHaveBeenCalledWith(owner, id, {
      version: 1,
      location: 'Office',
    });
  });
});
