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
import { AssetExportV4Controller } from './asset-export-v4.controller';
import { AssetExportV4Repository } from './asset-export-v4.repository';

const owner = '507f1f77bcf86cd799439011';
describe('full export v4 HTTP contract with synthetic auth and mocked SQL', () => {
  let app: NestExpressApplication;
  const exportSnapshot = jest.fn();
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [AssetExportV4Controller],
      providers: [
        {
          provide: AssetExportV4Repository,
          useValue: { exportSnapshot },
        },
      ],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate(context: ExecutionContext) {
          const req = context.switchToHttp().getRequest<{
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
      .get('/api/v1/assets/export/v4')
      .expect(401);
    expect(exportSnapshot).not.toHaveBeenCalled();
  });
  it.each([
    'q=filtered',
    'owner=other',
    'offset=0',
    'checkMode=all',
    'x[y]=z',
    'q=a&q=b',
  ])('rejects any query %s before SQL', async (query) => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/export/v4?' + query)
      .auth('synthetic', { type: 'bearer' })
      .expect(400);
    expect(exportSnapshot).not.toHaveBeenCalled();
  });
  it('returns only the authenticated complete snapshot with no-store', async () => {
    const response = await request(app.getHttpServer())
      .get('/api/v1/assets/export/v4')
      .auth('synthetic', { type: 'bearer' })
      .expect(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body.format).toBe('asset-desk-inventory');
    expect(response.body.schemaVersion).toBe(4);
    expect(JSON.parse(response.body.payload)).toMatchObject({
      complete: true,
      recordCount: 0,
      records: [],
    });
    expect(exportSnapshot).toHaveBeenCalledWith(owner);
  });
});
