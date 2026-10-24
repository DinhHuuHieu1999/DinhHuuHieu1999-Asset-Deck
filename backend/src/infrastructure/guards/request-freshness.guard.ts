import { BadRequestException, Injectable } from '@nestjs/common';
import type { CanActivate, ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';
import { Reflector } from '@nestjs/core';
import { IS_PUBLIC_KEY } from '../../shared/decorators/public.decorator';
import { getRequestSecurityConfig } from '../../app/config/runtime.config';

@Injectable()
export class RequestFreshnessGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const config = getRequestSecurityConfig();
    if (!config.freshnessEnabled) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const method = request.method.toUpperCase();
    if (
      !config.freshnessSafeMethods &&
      ['GET', 'HEAD', 'OPTIONS'].includes(method)
    ) {
      return true;
    }

    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const timestampHeader = request.headers[config.requestTimestampHeader];
    const timestampValue = Array.isArray(timestampHeader)
      ? timestampHeader[0]
      : timestampHeader;
    if (!timestampValue) {
      throw new BadRequestException(
        `${config.requestTimestampHeader} header is required`,
      );
    }

    const timestampMs = this.parseTimestamp(timestampValue);
    if (!timestampMs) {
      throw new BadRequestException(
        `${config.requestTimestampHeader} header is invalid`,
      );
    }

    const ageMs = Math.abs(Date.now() - timestampMs);
    if (ageMs > config.maxAgeMs) {
      throw new BadRequestException('Request timestamp is expired');
    }

    return true;
  }

  private parseTimestamp(value: string) {
    if (/^\d+$/.test(value)) {
      const numeric = Number(value);
      if (!Number.isFinite(numeric)) return null;
      return numeric > 10_000_000_000 ? numeric : numeric * 1000;
    }

    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
}
