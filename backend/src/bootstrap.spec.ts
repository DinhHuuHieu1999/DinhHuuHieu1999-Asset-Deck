import { AssetImportV3Module } from './domains/assets/asset-import-v3.module';
import { AssetExportV3Module } from './domains/assets/asset-export-v3.module';
import { AssetLocationModule } from './domains/assets/asset-location.module';
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
  const originalImportV3 = process.env.ASSET_IMPORT_V3_ENABLED;
  const originalExportV3 = process.env.ASSET_EXPORT_V3_ENABLED;
  const original = process.env.ASSET_IMPORT_ENABLED;
  const originalDates = process.env.ASSET_DATES_ENABLED;
  const originalV2 = process.env.ASSET_IMPORT_V2_ENABLED;
  const originalLocation = process.env.ASSET_LOCATION_ENABLED;
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
    delete process.env.ASSET_IMPORT_V3_ENABLED;
    delete process.env.ASSET_EXPORT_V3_ENABLED;
    delete process.env.ASSET_LOCATION_ENABLED;
    delete process.env.ASSET_IMPORT_ENABLED;
    delete process.env.ASSET_IMPORT_V2_ENABLED;
    delete process.env.ASSET_DATES_ENABLED;
    jest.mocked(NestFactory.create).mockResolvedValue(app as never);
    app.listen.mockResolvedValue(undefined);
    app.close.mockResolvedValue(undefined);
  });
  afterEach(() => {
    if (originalImportV3 === undefined)
      delete process.env.ASSET_IMPORT_V3_ENABLED;
    else process.env.ASSET_IMPORT_V3_ENABLED = originalImportV3;
    if (originalExportV3 === undefined)
      delete process.env.ASSET_EXPORT_V3_ENABLED;
    else process.env.ASSET_EXPORT_V3_ENABLED = originalExportV3;
    if (originalLocation === undefined)
      delete process.env.ASSET_LOCATION_ENABLED;
    else process.env.ASSET_LOCATION_ENABLED = originalLocation;
    if (originalV2 === undefined) delete process.env.ASSET_IMPORT_V2_ENABLED;
    else process.env.ASSET_IMPORT_V2_ENABLED = originalV2;
    if (originalDates === undefined) delete process.env.ASSET_DATES_ENABLED;
    else process.env.ASSET_DATES_ENABLED = originalDates;
    if (original === undefined) delete process.env.ASSET_IMPORT_ENABLED;
    else process.env.ASSET_IMPORT_ENABLED = original;
  });
  it('registers import v3 with its parser only when all prerequisites are enabled', async () => {
    process.env.ASSET_IMPORT_V3_ENABLED = 'true';
    process.env.ASSET_IMPORT_ENABLED = 'true';
    process.env.ASSET_DATES_ENABLED = 'true';
    process.env.ASSET_LOCATION_ENABLED = 'true';
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      {
        module: AppModule,
        imports: [
          AssetImportModule,
          AssetDatesModule,
          AssetImportV3Module,
          AssetLocationModule,
        ],
      },
      { bodyParser: true, abortOnError: false },
    );
    expect(app.use).toHaveBeenCalledTimes(4);
  });
  it.each(['import', 'dates', 'location'])(
    'refuses import v3 without %s before app construction',
    async (missing) => {
      process.env.ASSET_IMPORT_V3_ENABLED = 'true';
      process.env.ASSET_IMPORT_ENABLED =
        missing === 'import' ? 'false' : 'true';
      process.env.ASSET_DATES_ENABLED = missing === 'dates' ? 'false' : 'true';
      process.env.ASSET_LOCATION_ENABLED =
        missing === 'location' ? 'false' : 'true';
      await expect(bootstrap()).rejects.toThrow(
        'requires import, dates and location',
      );
      expect(NestFactory.create).not.toHaveBeenCalled();
    },
  );
  it('refuses malformed import v3 before app construction', async () => {
    process.env.ASSET_IMPORT_V3_ENABLED = 'TRUE';
    await expect(bootstrap()).rejects.toThrow('must be true or false');
    expect(NestFactory.create).not.toHaveBeenCalled();
  });
  it('registers v3 export only with both required capabilities and no import parser', async () => {
    process.env.ASSET_EXPORT_V3_ENABLED = 'true';
    process.env.ASSET_DATES_ENABLED = 'true';
    process.env.ASSET_LOCATION_ENABLED = 'true';
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      {
        module: AppModule,
        imports: [AssetExportV3Module, AssetDatesModule, AssetLocationModule],
      },
      { bodyParser: true, abortOnError: false },
    );
    expect(app.use).toHaveBeenCalledTimes(2);
  });
  it.each(['dates', 'location'])(
    'refuses v3 when %s is missing before constructing an app',
    async (missing) => {
      process.env.ASSET_EXPORT_V3_ENABLED = 'true';
      process.env.ASSET_DATES_ENABLED = missing === 'dates' ? 'false' : 'true';
      process.env.ASSET_LOCATION_ENABLED =
        missing === 'location' ? 'false' : 'true';
      await expect(bootstrap()).rejects.toThrow('requires dates and location');
      expect(NestFactory.create).not.toHaveBeenCalled();
    },
  );
  it('refuses malformed v3 enablement before constructing an app', async () => {
    process.env.ASSET_EXPORT_V3_ENABLED = 'TRUE';
    await expect(bootstrap()).rejects.toThrow('ASSET_EXPORT_V3_ENABLED');
    expect(NestFactory.create).not.toHaveBeenCalled();
  });
  it('registers only the location module when explicitly enabled', async () => {
    process.env.ASSET_LOCATION_ENABLED = 'true';
    await bootstrap();
    expect(NestFactory.create).toHaveBeenCalledWith(
      { module: AppModule, imports: [AssetLocationModule] },
      { bodyParser: true, abortOnError: false },
    );
  });
  it('refuses ambiguous location flags before app construction', async () => {
    process.env.ASSET_LOCATION_ENABLED = 'TRUE';
    await expect(bootstrap()).rejects.toThrow('ASSET_LOCATION_ENABLED');
    expect(NestFactory.create).not.toHaveBeenCalled();
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
