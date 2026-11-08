import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import {
  UnauthorizedException,
  ValidationPipe,
  type ExecutionContext,
} from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import request from 'supertest';
import { JwtAuthGuard } from '../../infrastructure/guards/jwt-auth.guard';
import { AssetSelectionExportController } from './asset-selection-export.controller';
import { AssetSelectionExportRepository } from './asset-selection-export.repository';

const owner = '507f1f77bcf86cd799439011';
describe('selection HTTP contract with synthetic auth and mocked SQL', () => {
  let app: NestExpressApplication;
  const exportSnapshot = jest.fn();
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [AssetSelectionExportController],
      providers: [
        {
          provide: AssetSelectionExportRepository,
          useValue: { exportSnapshot },
        },
      ],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate(context: ExecutionContext) {
          const req = context
            .switchToHttp()
            .getRequest<{
              headers: Record<string, string>;
              user?: { userId: string };
            }>();
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
    await app.init();
  });
  afterAll(async () => {
    await app?.close();
  });
  beforeEach(() => {
    exportSnapshot.mockReset();
    exportSnapshot.mockResolvedValue({
      exportedAt: '2026-10-29T00:00:00Z',
      records: [],
    });
  });
  it('rejects anonymous requests before persistence', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/export/selection')
      .expect(401);
    expect(exportSnapshot).not.toHaveBeenCalled();
  });
  it.each([
    'owner=other',
    'offset=0',
    'q=a&q=b',
    'q[x]=a',
    'sort=name_asc&sort=updated_desc',
    'locationMode=exact',
    'locationMode=unknown&location=A',
    'warranty=expired',
    'asOf=2026-10-29',
    'warranty=expired&asOf=2026-02-30',
  ])('rejects invalid HTTP query %s', async (query) => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/export/selection?' + query)
      .auth('synthetic', { type: 'bearer' })
      .expect(400);
    expect(exportSnapshot).not.toHaveBeenCalled();
  });
  it('returns a no-store separate envelope with literal filters and fixed owner', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/assets/export/selection')
      .query({
        q: '%_',
        locationMode: 'exact',
        location: 'Room %_1',
        sort: 'name_asc',
        warranty: 'expiring_soon',
        asOf: '2026-10-29',
      })
      .auth('synthetic', { type: 'bearer' })
      .expect(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body.format).toBe('asset-desk-inventory-selection');
    const payload = JSON.parse(response.body.payload);
    expect(payload).not.toHaveProperty('complete');
    expect(payload.recordCount).toBe(0);
    expect(exportSnapshot).toHaveBeenCalledWith(
      owner,
      expect.objectContaining({
        q: '%_',
        location: 'Room %_1',
        sort: 'name_asc',
        warranty: {
          filter: 'expiring_soon',
          asOf: '2026-10-29',
          through: '2026-11-28',
        },
      }),
    );
  });
});
