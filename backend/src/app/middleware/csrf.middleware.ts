import { Injectable } from '@nestjs/common';
import type { NestMiddleware } from '@nestjs/common';
import type { NextFunction, Request, Response } from 'express';
import { CsrfService } from '../services/csrf.service';

@Injectable()
export class CsrfMiddleware implements NestMiddleware {
  constructor(private readonly csrfService: CsrfService) {}

  use(req: Request, res: Response, next: NextFunction) {
    if (process.env.CSRF_ENABLED !== 'true') {
      next();
      return;
    }
    this.csrfService.doubleCsrfProtection(req, res, next);
  }
}
