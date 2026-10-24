import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Strategy } from 'passport-local';
import { AuthService } from '../../domains/auth/auth.service';
import type { roleAuthEnum } from '../../shared/enums/role-auth.enum';

interface LocalAuthUser {
  userId: string;
  email: string;
  role: roleAuthEnum;
}

@Injectable()
export class LocalStrategy extends PassportStrategy(Strategy) {
  constructor(private authService: AuthService) {
    super({ usernameField: 'identifier' });
  }

  async validate(identifier: string, password: string): Promise<LocalAuthUser> {
    const { user } = await this.authService.login({ identifier, password });
    if (!user) throw new UnauthorizedException();
    return { userId: user.id, email: user.email, role: user.role };
  }
}
