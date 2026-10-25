import 'reflect-metadata';
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
  const importEnabled = isAssetImportEnabled();
  const app = await NestFactory.create<NestExpressApplication>(
    {
      module: AppModule,
      imports: importEnabled ? [AssetImportModule] : [],
    },
    {
      bodyParser: true,
      abortOnError: false,
    },
  );
  try {
    // Install before Nest initialization so only this route gets a larger parser.
    if (importEnabled) app.use(createAssetImportParser());
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
