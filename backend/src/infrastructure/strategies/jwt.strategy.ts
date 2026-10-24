import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { jwtVerify, type JWTPayload } from 'jose';
import { AccountRepository } from '../../domains/auth/account.repository';
import { statusAuthEnum } from '../../shared/enums/status-auth.enum';
import { resolveJwtAccessSecret } from '../../app/config/jwt.config';
interface StrategyRequest {
  headers?: { authorization?: string | string[] };
}
interface JoseStrategyOptions {
  jwtFromRequest?: (request: StrategyRequest) => string | null;
  secretOrKey: string;
  passReqToCallback?: boolean;
}
type VerifyCallback = (
  error: Error | null,
  user?: unknown,
  info?: unknown,
) => void;
type VerifyFunction = (...args: unknown[]) => void;
interface AuthenticatedUser {
  userId: string;
  role: string;
  email: string;
  username: string;
  name: string;
}
// Minimal Passport strategy base — fail/success/error được passport inject runtime
abstract class BaseStrategy {
  name?: string;
  abstract authenticate(_req: StrategyRequest, _options?: unknown): void;
  fail(_info: unknown, _status?: number): void {
    /* injected by passport */
  }
  success(_user: unknown, _info?: unknown): void {
    /* injected by passport */
  }
  error(_err: unknown): void {
    /* injected by passport */
  }
}
class JoseJwtStrategy extends BaseStrategy {
  name = 'jwt';
  private jwtFromRequest: (req: StrategyRequest) => string | null;
  private verify: VerifyFunction;
  private secret: Uint8Array;
  private passReqToCallback: boolean;
  constructor(options: JoseStrategyOptions, verify: VerifyFunction) {
    super();
    if (!options.jwtFromRequest) {
      throw new TypeError('JwtStrategy requires a jwtFromRequest option');
    }
    this.jwtFromRequest = options.jwtFromRequest;
    this.verify = verify;
    this.passReqToCallback = options.passReqToCallback ?? false;
    this.secret = new TextEncoder().encode(String(options.secretOrKey || ''));
  }
  async authenticate(req: StrategyRequest) {
    try {
      const token = this.jwtFromRequest(req);
      if (!token) {
        this.fail({ message: 'No auth token' }, 401);
        return;
      }
      const { payload } = await jwtVerify(token, this.secret);
      const verified: VerifyCallback = (err, user, info) => {
        if (err) {
          this.error(err);
          return;
        }
        if (!user) {
          this.fail(info);
          return;
        }
        this.success(user, info);
      };
      if (this.passReqToCallback) {
        this.verify(req, payload, verified);
      } else {
        this.verify(payload, verified);
      }
    } catch {
      this.fail({ message: 'Invalid token' }, 401);
      return;
    }
  }
}
@Injectable()
export class JwtStrategy extends PassportStrategy(JoseJwtStrategy, 'jwt') {
  constructor(
    configService: ConfigService,
    @Inject(AccountRepository) private readonly accounts: AccountRepository,
  ) {
    super({
      jwtFromRequest: (req: StrategyRequest) => {
        const header = req.headers?.authorization;
        if (typeof header !== 'string') return null;
        const match = header.match(/^Bearer (.+)$/i);
        return match ? match[1] : null;
      },
      secretOrKey: resolveJwtAccessSecret(
        configService.get<string>('JWT_ACCESS_SECRET'),
        configService.get<string>('NODE_ENV'),
      ),
    });
  }
  async validate(payload: JWTPayload): Promise<AuthenticatedUser> {
    if (typeof payload.sub !== 'string' || typeof payload.role !== 'string') {
      throw new UnauthorizedException('Invalid token payload');
    }
    const user = await this.accounts.findById(payload.sub);
    if (
      !user ||
      user.status !== statusAuthEnum.ACTIVE ||
      user.requireReverify
    ) {
      throw new UnauthorizedException('Account is not active');
    }
    return {
      userId: payload.sub,
      role: user.role,
      email: user.email,
      username: user.username,
      name: user.name,
    };
  }
}
