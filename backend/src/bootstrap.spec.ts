import { AssetImportV2Module } from './domains/assets/asset-import-v2.module';
import { AssetDatesModule } from './domains/assets/asset-dates.module';
jest.mock('./app/modules/app.module', () => ({
  AppModule: class AppModule {},
}));
jest.mock('./domains/auth/auth.module', () => ({
  AuthModule: class AuthModule {},
}));
import { NestFactory } from '@nestjs/core';
import { bootstrap } from './main';
import { AssetImportModule } from './domains/assets/asset-import.module';
import { AppModule } from './app/modules/app.module';

jest.mock('./app/config/env-files', () => ({ loadEnvFiles: jest.fn() }));
jest.mock('./app/config/startup.config', () => ({
  validateStartup: () => 8180,
}));
jest.mock('@nestjs/core', () => ({
  ...jest.requireActual('@nestjs/core'),
  NestFactory: { create: jest.fn() },
}));

describe('opt-in import bootstrap', () => {
  const original = process.env.ASSET_IMPORT_ENABLED;
  const originalDates = process.env.ASSET_DATES_ENABLED;
  const originalV2 = process.env.ASSET_IMPORT_V2_ENABLED;
  const app = {
    use: jest.fn(),
    set: jest.fn(),
    setGlobalPrefix: jest.fn(),
    useGlobalPipes: jest.fn(),
    enableShutdownHooks: jest.fn(),
    listen: jest.fn(),
    close: jest.fn(),
  };
  beforeEach(() => {
    jest.clearAllMocks();
    delete process.env.ASSET_IMPORT_ENABLED;
    delete process.env.ASSET_IMPORT_V2_ENABLED;
    delete process.env.ASSET_DATES_ENABLED;
    jest.mocked(NestFactory.create).mockResolvedValue(app as never);
    app.listen.mockResolvedValue(undefined);
    app.close.mockResolvedValue(undefined);
  });
  afterEach(() => {
    if (originalV2 === undefined) delete process.env.ASSET_IMPORT_V2_ENABLED;
    else process.env.ASSET_IMPORT_V2_ENABLED = originalV2;
    if (originalDates === undefined) delete process.env.ASSET_DATES_ENABLED;
    else process.env.ASSET_DATES_ENABLED = originalDates;
    if (original === undefined) delete process.env.ASSET_IMPORT_ENABLED;
    else process.env.ASSET_IMPORT_ENABLED = original;
  });
  it('registers v2 only with all three flags and its separate parser', async () => {
    process.env.ASSET_IMPORT_ENABLED = 'true';
    process.env.ASSET_DATES_ENABLED = 'true';
    process.env.ASSET_IMPORT_V2_ENABLED = 'true';
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      {
        module: AppModule,
        imports: [AssetImportModule, AssetDatesModule, AssetImportV2Module],
      },
      { bodyParser: true, abortOnError: false },
    );
    expect(app.use).toHaveBeenCalledTimes(4);
  });
  it('refuses inconsistent v2 configuration before constructing an app', async () => {
    process.env.ASSET_IMPORT_V2_ENABLED = 'true';
    await expect(bootstrap()).rejects.toThrow('requires import and dates');
    expect(NestFactory.create).not.toHaveBeenCalled();
  });
  it('registers date capability only under its explicit flag without the import parser', async () => {
    process.env.ASSET_DATES_ENABLED = 'true';
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      { module: AppModule, imports: [AssetDatesModule] },
      { bodyParser: true, abortOnError: false },
    );
    expect(app.use).toHaveBeenCalledTimes(2);
  });
  it('supports both independently enabled capabilities', async () => {
    process.env.ASSET_DATES_ENABLED = 'true';
    process.env.ASSET_IMPORT_ENABLED = 'true';
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      { module: AppModule, imports: [AssetImportModule, AssetDatesModule] },
      { bodyParser: true, abortOnError: false },
    );
  });
  it('rejects malformed date enablement before constructing the app', async () => {
    process.env.ASSET_DATES_ENABLED = 'TRUE';
    await expect(bootstrap()).rejects.toThrow('ASSET_DATES_ENABLED');
    expect(NestFactory.create).not.toHaveBeenCalled();
  });
  it('does not register the write capability by default', async () => {
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      { module: AppModule, imports: [] },
      { bodyParser: true, abortOnError: false },
    );
    expect(app.use).toHaveBeenCalledTimes(2);
    expect(app.listen).toHaveBeenCalledWith(8180, '127.0.0.1');
    expect(app.close).not.toHaveBeenCalled();
  });
  it('registers the separate module and parser before listening only when enabled', async () => {
    process.env.ASSET_IMPORT_ENABLED = 'true';
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      { module: AppModule, imports: [AssetImportModule] },
      { bodyParser: true, abortOnError: false },
    );
    expect(app.use).toHaveBeenCalledTimes(3);
    expect(app.use.mock.invocationCallOrder[0]).toBeLessThan(
      app.listen.mock.invocationCallOrder[0],
    );
  });
  it('rejects ambiguous configuration before creating an application', async () => {
    process.env.ASSET_IMPORT_ENABLED = 'TRUE';
    await expect(bootstrap()).rejects.toThrow('ASSET_IMPORT_ENABLED');
    expect(NestFactory.create).not.toHaveBeenCalled();
  });
  it('closes the application on startup failure without replacing that failure', async () => {
    const failure = new Error('synthetic startup failure');
    app.listen.mockRejectedValueOnce(failure);
    app.close.mockRejectedValueOnce(new Error('synthetic close failure'));
    await expect(bootstrap()).rejects.toBe(failure);
    expect(app.close).toHaveBeenCalledTimes(1);
  });
  it('closes the created app on initialization/listen failure', async () => {
    const failure = new Error('synthetic listen failure');
    app.listen.mockRejectedValueOnce(failure);
    await expect(bootstrap()).rejects.toBe(failure);
    expect(app.close).toHaveBeenCalledTimes(1);
  });
  it('does not close an application the factory never returned', async () => {
    const failure = new Error('synthetic factory failure');
    jest.mocked(NestFactory.create).mockRejectedValueOnce(failure);
    await expect(bootstrap()).rejects.toBe(failure);
    expect(app.close).not.toHaveBeenCalled();
  });
});
