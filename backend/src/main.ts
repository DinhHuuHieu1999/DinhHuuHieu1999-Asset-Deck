import { AssetSavedFilterModule } from './domains/assets/asset-saved-filter.module';
import { isAssetSavedFilterEnabled } from './domains/assets/asset-saved-filter.config';
import { AssetImportV4Module } from './domains/assets/asset-import-v4.module';
import { isAssetImportV4Enabled } from './domains/assets/asset-import-v4.config';
import { createAssetImportV4Parser } from './domains/assets/asset-import-v4-parser';
import { AssetExportV4Module } from './domains/assets/asset-export-v4.module';
import { isAssetExportV4Enabled } from './domains/assets/asset-export-v4.config';
import { AssetSelectionExportV2Module } from './domains/assets/asset-selection-export-v2.module';
import { isAssetSelectionExportV2Enabled } from './domains/assets/asset-selection-export-v2.config';
import { AssetCheckModule } from './domains/assets/asset-check.module';
import { isAssetCheckEnabled } from './domains/assets/asset-check';
import { AssetSelectionExportModule } from './domains/assets/asset-selection-export.module';
import { isAssetSelectionExportEnabled } from './domains/assets/asset-selection-export.config';
import { AssetImportV3Module } from './domains/assets/asset-import-v3.module';
import { isAssetImportV3Enabled } from './domains/assets/asset-import-v3.config';
import { createAssetImportV3Parser } from './domains/assets/asset-import-v3-parser';
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
export async function bootstrap(): Promise<NestExpressApplication> {
  loadEnvFiles();
  const port = validateStartup();
  const savedFiltersEnabled = isAssetSavedFilterEnabled();
  const selectionExportV2Enabled = isAssetSelectionExportV2Enabled();
  const selectionExportEnabled = isAssetSelectionExportEnabled();
  const exportV4Enabled = isAssetExportV4Enabled();
  const exportV3Enabled = isAssetExportV3Enabled();
  const locationEnabled = isAssetLocationEnabled();
  const checkEnabled = isAssetCheckEnabled();
  const importEnabled = isAssetImportEnabled();
  const datesEnabled = isAssetDatesEnabled();
  const importV3Enabled = isAssetImportV3Enabled();
  const importV4Enabled = isAssetImportV4Enabled();
  const importV2Enabled = isAssetImportV2Enabled();
  const app = await NestFactory.create<NestExpressApplication>(
    {
      module: AppModule,
      imports: [
        ...(savedFiltersEnabled ? [AssetSavedFilterModule] : []),
        ...(selectionExportV2Enabled ? [AssetSelectionExportV2Module] : []),
        ...(selectionExportEnabled ? [AssetSelectionExportModule] : []),
        ...(exportV4Enabled ? [AssetExportV4Module] : []),
        ...(exportV3Enabled ? [AssetExportV3Module] : []),
        ...(importEnabled ? [AssetImportModule] : []),
        ...(datesEnabled ? [AssetDatesModule] : []),
        ...(importV2Enabled ? [AssetImportV2Module] : []),
        ...(importV3Enabled ? [AssetImportV3Module] : []),
        ...(importV4Enabled ? [AssetImportV4Module] : []),
        ...(locationEnabled ? [AssetLocationModule] : []),
        ...(checkEnabled ? [AssetCheckModule] : []),
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
    if (importV3Enabled) app.use(createAssetImportV3Parser());
    if (importV4Enabled) app.use(createAssetImportV4Parser());
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
    return app;
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
