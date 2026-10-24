import { ForbiddenException, Injectable } from '@nestjs/common';
import type { CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { IS_PUBLIC_KEY } from '../../shared/decorators/public.decorator';
import type { Request } from 'express';

@Injectable()
export class IpWhitelistGuard implements CanActivate {
  private whitelistCache: Set<string> | null = null;

  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const whitelist = this.getWhitelist();
    if (whitelist.size === 0) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const requestIp = this.extractClientIp(request);

    if (!requestIp || !whitelist.has(requestIp)) {
      throw new ForbiddenException('IP is not in whitelist');
    }

    return true;
  }

  private getWhitelist(): Set<string> {
    if (this.whitelistCache) return this.whitelistCache;

    const raw = process.env.IP_WHITELIST?.trim();
    if (!raw) {
      this.whitelistCache = new Set<string>();
      return this.whitelistCache;
    }

    this.whitelistCache = new Set(
      raw
        .split(',')
        .map((ip) => ip.trim())
        .filter(Boolean),
    );
    return this.whitelistCache;
  }

  private extractClientIp(request: Request): string | null {
    // Express resolves forwarded addresses using the configured trust-proxy boundary.
    // Reading the raw header here would let an untrusted client bypass the whitelist.
    const rawIp = request.ip;
    if (!rawIp) return null;

    return rawIp.replace('::ffff:', '');
  }
}
