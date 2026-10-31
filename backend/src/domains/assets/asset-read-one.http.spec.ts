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
import { AssetsController } from './assets.controller';
import { AssetsService } from './assets.service';
import { AssetsRepository } from './assets.repository';

const owner = '507f1f77bcf86cd799439011';
const id = 'a0000000-0000-4000-8000-000000000001';
describe('single-asset HTTP with synthetic auth and mocked persistence', () => {
  let app: NestExpressApplication;
  const findOne = jest.fn();
  const serialDuplicate = jest.fn().mockResolvedValue({ duplicate: false });
  beforeAll(async () => {
    const module = await Test.createTestingModule({
      controllers: [AssetsController],
      providers: [
        {
          provide: AssetsService,
          useFactory: () =>
            new AssetsService({
              ready: async () => undefined,
              findOne,
              serialDuplicate,
            } as unknown as AssetsRepository),
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
    findOne.mockReset();
    serialDuplicate.mockClear();
  });
  it('rejects anonymous requests and malformed UUIDs before repository reads', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/' + id)
      .expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/assets/not-a-uuid')
      .auth('synthetic', { type: 'bearer' })
      .expect(400);
    expect(findOne).not.toHaveBeenCalled();
  });
  it('returns the owner-scoped base record with no-store', async () => {
    const record = { id, name: 'Synthetic', version: 1 };
    findOne.mockResolvedValue(record);
    const response = await request(app.getHttpServer())
      .get('/api/v1/assets/' + id)
      .query({ owner: 'other' })
      .auth('synthetic', { type: 'bearer' })
      .expect(200);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(response.body).toEqual(record);
    expect(findOne).toHaveBeenCalledWith(owner, id);
  });
  it('unavailable records return the same bounded not-found body', async () => {
    findOne.mockResolvedValue(null);
    const responses = [];
    for (const target of [id, 'b0000000-0000-4000-8000-000000000001']) {
      responses.push(
        (
          await request(app.getHttpServer())
            .get('/api/v1/assets/' + target)
            .auth('synthetic', { type: 'bearer' })
            .expect(404)
        ).body,
      );
    }
    expect(responses[0]).toEqual(responses[1]);
    expect(responses[0].message).toBe('Asset is unavailable');
  });
  it('static serial route is not captured by the UUID route', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/assets/serial-duplicates')
      .query({ serial: '%_' })
      .auth('synthetic', { type: 'bearer' })
      .expect(200);
    expect(findOne).not.toHaveBeenCalled();
    expect(serialDuplicate).toHaveBeenCalledWith(owner, '%_', undefined);
  });
});
