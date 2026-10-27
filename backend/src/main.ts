import 'reflect-metadata';
import { AssetExportV3Module } from './domains/assets/asset-export-v3.module';
import { isAssetExportV3Enabled } from './domains/assets/asset-export-v3.config';
import { AssetLocationModule } from './domains/assets/asset-location.module';
import { isAssetLocationEnabled } from './domains/assets/asset-location.config';
import { AssetImportV2Module } from './domains/assets/asset-import-v2.module';
import { isAssetImportV2Enabled } from './domains/assets/asset-import-v2.config';
import { createAssetImportV2Parser } from './domains/assets/asset-import-v2-parser';
import { AssetDatesModule } from './domains/assets/asset-dates.module';
import { isAssetDatesEnabled } from './domains/assets/asset-dates.config';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import cookieParser from 'cookie-parser';
import helmet from 'helmet';
import { loadEnvFiles } from './app/config/env-files';
import { validateStartup } from './app/config/startup.config';
import { AppModule } from './app/modules/app.module';
import { AssetImportModule } from './domains/assets/asset-import.module';
import { isAssetImportEnabled } from './domains/assets/asset-import.config';
import { createAssetImportParser } from './domains/assets/asset-import-parser';

/** Start a loopback-only API; release clients require an external HTTPS endpoint. */
export async function bootstrap(): Promise<void> {
  loadEnvFiles();
  const port = validateStartup();
  const exportV3Enabled = isAssetExportV3Enabled();
  const locationEnabled = isAssetLocationEnabled();
  const importEnabled = isAssetImportEnabled();
  const datesEnabled = isAssetDatesEnabled();
  const importV2Enabled = isAssetImportV2Enabled();
  const app = await NestFactory.create<NestExpressApplication>(
    {
      module: AppModule,
      imports: [
        ...(exportV3Enabled ? [AssetExportV3Module] : []),
        ...(importEnabled ? [AssetImportModule] : []),
        ...(datesEnabled ? [AssetDatesModule] : []),
        ...(importV2Enabled ? [AssetImportV2Module] : []),
        ...(locationEnabled ? [AssetLocationModule] : []),
      ],
    },
    {
      bodyParser: true,
      abortOnError: false,
    },
  );
  try {
    // Install before Nest initialization so only this route gets a larger parser.
    if (importEnabled) app.use(createAssetImportParser());
    if (importV2Enabled) app.use(createAssetImportV2Parser());
    app.set('trust proxy', false);
    app.use(helmet());
    app.use(cookieParser());
    app.setGlobalPrefix('api/v1');
    app.useGlobalPipes(
      new ValidationPipe({
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
      }),
    );
    app.enableShutdownHooks();
    await app.listen(port, '127.0.0.1');
  } catch (error) {
    try {
      await app.close();
    } catch {
      // Preserve the startup failure without exposing private cleanup details.
    }
    throw error;
  }
}

if (require.main === module) {
  void bootstrap().catch(() => {
    // Avoid logging private connection details or submitted values on startup failure.
    console.error(
      'Asset Desk startup failed; check configuration and schema readiness',
    );
    process.exitCode = 1;
  });
}
