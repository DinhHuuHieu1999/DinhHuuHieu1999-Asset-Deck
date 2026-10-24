import {
  Controller,
  Get,
  Header,
  Req,
  Res,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { Public } from '../shared/decorators/public.decorator';
import { CsrfService } from './services/csrf.service';
import { PostgresDatabase } from '../infrastructure/database/postgres.database';

/** Minimal readiness and CSRF token endpoints, without account metrics. */
@Controller()
export class SystemController {
  constructor(
    private readonly csrf: CsrfService,
    private readonly database: PostgresDatabase,
  ) {}

  /** Issue the existing cookie/header CSRF contract; never cache the token. */
  @Public()
  @Get('csrf-token')
  @Header('Cache-Control', 'no-store')
  token(@Req() req: Request, @Res({ passthrough: true }) res: Response) {
    return { token: this.csrf.generateCsrfToken(req, res) };
  }

  /** Verify storage readiness without returning connection or account details. */
  @Public()
  @Get('health')
  @Header('Cache-Control', 'no-store')
  async health() {
    if (!(await this.database.isReady()))
      throw new ServiceUnavailableException('Storage unavailable');
    return { status: 'ready' };
  }
}
