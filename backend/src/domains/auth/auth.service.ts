import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { SignJWT } from 'jose';
import { resolveJwtAccessSecret } from '../../app/config/jwt.config';
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import type { Cache } from 'cache-manager';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { roleAuthEnum } from '../../shared/enums/role-auth.enum';
import { statusAuthEnum } from '../../shared/enums/status-auth.enum';
import { ChangePasswordDto } from './dto/change-password.dto';
import { AdminCreateUserDto } from './dto/admin-create-user.dto';
import { AdminListUsersDto } from './dto/admin-list-users.dto';
import { AdminUpdateUserStatusDto } from './dto/admin-update-user-status.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import {
  AccountRepository,
  type Account,
  type AccountFilter,
} from './account.repository';
import { ensurePasswordChanged } from './auth-password.util';
import { shouldExposeResetToken } from './auth-reset.util';
@Injectable()
export class AuthService {
  constructor(
    private readonly accounts: AccountRepository,
    @Inject(CACHE_MANAGER) private readonly cache: Cache,
  ) {}
  async register(payload: RegisterDto) {
    const email = payload.email.trim().toLowerCase();
    const username = payload.username.trim().toLowerCase();
    const existing = await this.accounts.findByIdentity(email, username);
    if (existing) {
      if (existing.email === email) {
        throw new BadRequestException('Email already exists');
      }
      throw new BadRequestException('Username already exists');
    }
    const passwordHash = await this.hashPassword(payload.password);
    const created = await this.accounts.create({
      email,
      username,
      name: payload.name.trim(),
      passwordHash,
      role: roleAuthEnum.USER,
      status: statusAuthEnum.ACTIVE,
    });
    const accessToken = await this.signAccessToken(
      created.id,
      created.email,
      created.role,
      created.username,
      created.name,
    );
    return {
      message: 'Register successful',
      accessToken,
      user: this.toPublicUser(created),
    };
  }
  async login(payload: LoginDto) {
    const identifier = payload.identifier.trim().toLowerCase();
    const user = await this.accounts.findByIdentity(identifier, identifier);
    if (!user) throw new UnauthorizedException('Invalid credentials');
    const now = Date.now();
    if (user.lockUntil && user.lockUntil.getTime() > now) {
      const waitMinutes = Math.ceil((user.lockUntil.getTime() - now) / 60000);
      throw new UnauthorizedException(
        `Account temporarily locked. Try again in ${waitMinutes} minute(s)`,
      );
    }
    if (this.shouldRequireReverify(user.lastLoginAt)) {
      user.requireReverify = true;
      await this.accounts.save(user);
      throw new UnauthorizedException(
        'Account inactive for too long. Please reset password to verify account',
      );
    }
    const isValid = await bcrypt.compare(payload.password, user.passwordHash);
    if (!isValid) {
      await this.handleFailedLogin(user);
      throw new UnauthorizedException('Invalid credentials');
    }
    if (user.status !== statusAuthEnum.ACTIVE) {
      throw new UnauthorizedException('Account is not active');
    }
    if (user.requireReverify) {
      throw new UnauthorizedException(
        'Account requires re-verification. Please reset password',
      );
    }
    user.failedLoginAttempts = 0;
    user.lockUntil = undefined;
    user.lastLoginAt = new Date();
    user.requireReverify = false;
    await this.accounts.save(user);
    const accessToken = await this.signAccessToken(
      user.id,
      user.email,
      user.role,
      user.username,
      user.name,
    );
    return {
      message: 'Login successful',
      accessToken,
      user: this.toPublicUser(user),
    };
  }
  async loginPassport(userId: string, _email: string, _role: string) {
    const user = await this.accounts.findById(userId);
    if (!user) throw new NotFoundException('User not found');
    if (this.shouldRequireReverify(user.lastLoginAt)) {
      user.requireReverify = true;
      await this.accounts.save(user);
      throw new UnauthorizedException(
        'Account inactive for too long. Please reset password to verify account',
      );
    }
    if (user.requireReverify) {
      throw new UnauthorizedException(
        'Account requires re-verification. Please reset password',
      );
    }
    user.failedLoginAttempts = 0;
    user.lockUntil = undefined;
    user.lastLoginAt = new Date();
    user.requireReverify = false;
    await this.accounts.save(user);
    const accessToken = await this.signAccessToken(
      user.id,
      user.email,
      user.role,
      user.username,
      user.name,
    );
    return {
      message: 'Login successful',
      accessToken,
      user: this.toPublicUser(user),
    };
  }
  async getProfile(userId: string) {
    if (!userId) throw new UnauthorizedException('Unauthorized');
    const user = await this.accounts.findById(userId);
    if (!user) throw new NotFoundException('User not found');
    return { user: this.toPublicUser(user) };
  }
  async changePassword(userId: string, payload: ChangePasswordDto) {
    if (!userId) throw new UnauthorizedException('Unauthorized');
    const user = await this.accounts.findById(userId);
    if (!user) throw new NotFoundException('User not found');
    const isValidOldPassword = await bcrypt.compare(
      payload.currentPassword,
      user.passwordHash,
    );
    if (!isValidOldPassword) {
      throw new BadRequestException('Current password is incorrect');
    }
    ensurePasswordChanged(payload.currentPassword, payload.newPassword);
    user.passwordHash = await this.hashPassword(payload.newPassword);
    user.passwordChangedAt = new Date();
    user.resetPasswordTokenHash = undefined;
    user.resetPasswordExpiresAt = undefined;
    await this.accounts.save(user);
    return { message: 'Password updated' };
  }
  async forgotPassword(payload: ForgotPasswordDto) {
    const email = payload.email.trim().toLowerCase();
    const user = await this.accounts.findByEmail(email);
    if (!user) {
      return { message: 'If the email exists, reset instructions were issued' };
    }
    const rawToken = randomBytes(32).toString('base64url');
    const tokenHash = this.hashToken(rawToken);
    const expiresAt = new Date(
      Date.now() +
        Number(process.env.AUTH_RESET_TOKEN_TTL_MINUTES ?? 30) * 60 * 1000,
    );
    user.resetPasswordTokenHash = tokenHash;
    user.resetPasswordExpiresAt = expiresAt;
    await this.accounts.save(user);
    const response: Record<string, unknown> = {
      message: 'If the email exists, reset instructions were issued',
    };
    if (
      shouldExposeResetToken(
        process.env.NODE_ENV,
        process.env.AUTH_EXPOSE_RESET_TOKEN,
      )
    ) {
      response.debugResetToken = rawToken;
      response.debugResetExpiresAt = expiresAt.toISOString();
    }
    return response;
  }
  async resetPassword(payload: ResetPasswordDto) {
    const tokenHash = this.hashToken(payload.token);
    const user = await this.accounts.findByResetToken(tokenHash, new Date());
    if (!user) {
      throw new BadRequestException('Invalid or expired reset token');
    }
    user.passwordHash = await this.hashPassword(payload.newPassword);
    user.passwordChangedAt = new Date();
    user.resetPasswordTokenHash = undefined;
    user.resetPasswordExpiresAt = undefined;
    user.failedLoginAttempts = 0;
    user.lockLevel = 0;
    user.lockUntil = undefined;
    user.requireReverify = false;
    user.lastLoginAt = new Date();
    await this.accounts.save(user);
    return { message: 'Password has been reset' };
  }
  async adminCreateUser(payload: AdminCreateUserDto, requesterId: string) {
    if (!requesterId) throw new UnauthorizedException('Unauthorized');
    const email = payload.email.trim().toLowerCase();
    const username = payload.username.trim().toLowerCase();
    const existing = await this.accounts.findByIdentity(email, username);
    if (existing) {
      if (existing.email === email) {
        throw new BadRequestException('Email already exists');
      }
      throw new BadRequestException('Username already exists');
    }
    const passwordHash = await this.hashPassword(payload.password);
    const created = await this.accounts.create({
      email,
      username,
      name: payload.name.trim(),
      passwordHash,
      role: payload.role ?? roleAuthEnum.USER,
      status: payload.status ?? statusAuthEnum.ACTIVE,
    });
    await this.cache.clear();
    return {
      message: 'User created',
      user: this.toPublicUser(created),
    };
  }
  async adminListUsers(query: AdminListUsersDto) {
    const page = query.page ?? 1;
    const limit = query.limit ?? 20;
    const cacheKey = `admin-users:${page}:${limit}:${query.search ?? ''}:${query.role ?? ''}:${query.status ?? ''}`;
    const cached = await this.cache.get<{
      items: ReturnType<AuthService['toPublicUser']>[];
      pagination: {
        page: number;
        limit: number;
        total: number;
        totalPages: number;
      };
    }>(cacheKey);
    if (cached) return cached;
    const skip = (page - 1) * limit;
    const filter: AccountFilter = {
      role: query.role,
      status: query.status,
      search: query.search,
    };
    const [items, total] = await Promise.all([
      this.accounts.find(filter, { sort: 'createdAt', skip, limit }),
      this.accounts.count(filter),
    ]);
    const result = {
      items: items.map((item) => this.toPublicUser(item)),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.max(1, Math.ceil(total / limit)),
      },
    };
    await this.cache.set(cacheKey, result, 15_000);
    return result;
  }
  async adminUpdateUserStatus(
    userId: string,
    payload: AdminUpdateUserStatusDto,
    requesterId: string,
  ) {
    if (userId === requesterId) {
      throw new ForbiddenException('Admin cannot change own status');
    }
    const user = await this.accounts.findById(userId);
    if (!user) throw new NotFoundException('User not found');
    user.status = payload.status;
    if (payload.status !== statusAuthEnum.ACTIVE) {
      user.lockUntil = undefined;
    }
    await this.accounts.save(user);
    await this.cache.clear();
    return {
      message: 'User status updated',
      user: this.toPublicUser(user),
    };
  }
  private async signAccessToken(
    userId: string,
    email: string,
    role: roleAuthEnum,
    username: string,
    name: string,
  ) {
    const secret = new TextEncoder().encode(
      resolveJwtAccessSecret(
        process.env.JWT_ACCESS_SECRET,
        process.env.NODE_ENV,
      ),
    );
    const expiresIn = process.env.JWT_ACCESS_EXPIRES_IN ?? '15m';
    return new SignJWT({
      sub: userId,
      email,
      role,
      username,
      name,
    })
      .setProtectedHeader({ alg: 'HS256' })
      .setExpirationTime(expiresIn)
      .sign(secret);
  }
  private async hashPassword(password: string) {
    const rounds = Number(process.env.AUTH_BCRYPT_ROUNDS ?? 12);
    return bcrypt.hash(password, rounds);
  }
  private hashToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }
  private shouldRequireReverify(lastLoginAt?: Date) {
    const inactivityDays = Number(
      process.env.AUTH_INACTIVE_REVERIFY_DAYS ?? 90,
    );
    if (!Number.isFinite(inactivityDays) || inactivityDays <= 0) return false;
    if (!lastLoginAt) return false;
    const inactivityMs = inactivityDays * 24 * 60 * 60 * 1000;
    return Date.now() - lastLoginAt.getTime() > inactivityMs;
  }
  private async handleFailedLogin(user: Account) {
    const maxAttempts = Number(process.env.AUTH_LOGIN_MAX_ATTEMPTS_BASE ?? 5);
    const baseLockMinutes = Number(
      process.env.AUTH_LOGIN_LOCK_MINUTES_BASE ?? 5,
    );
    const maxLockMinutes = Number(
      process.env.AUTH_LOGIN_LOCK_MINUTES_MAX ?? 1440,
    );
    user.failedLoginAttempts = (user.failedLoginAttempts ?? 0) + 1;
    if (user.failedLoginAttempts >= maxAttempts) {
      user.lockLevel = (user.lockLevel ?? 0) + 1;
      const lockMinutes = Math.min(
        baseLockMinutes * Math.pow(2, user.lockLevel - 1),
        maxLockMinutes,
      );
      user.lockUntil = new Date(Date.now() + lockMinutes * 60 * 1000);
      user.failedLoginAttempts = 0;
    }
    await this.accounts.save(user);
  }
  async listUsers() {
    const users = await this.accounts.find(
      { status: statusAuthEnum.ACTIVE },
      { sort: 'name' },
    );
    return {
      users: users.map((user) => ({
        id: user.id,
        username: user.username,
        name: user.name,
        role: user.role,
      })),
    };
  }
  async getDashboardSummary(requesterId: string, requesterRole?: roleAuthEnum) {
    if (!requesterId) throw new UnauthorizedException('Unauthorized');
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    if (requesterRole !== roleAuthEnum.ADMINISTRATOR) {
      const user = await this.accounts.findById(requesterId);
      if (!user) throw new NotFoundException('User not found');
      const isActive = user.status === statusAuthEnum.ACTIVE;
      const loggedInRecently = Boolean(
        user.lastLoginAt && user.lastLoginAt >= thirtyDaysAgo,
      );
      const createdRecently = Boolean(
        user.createdAt && user.createdAt >= thirtyDaysAgo,
      );
      return {
        metrics: {
          activeAccounts: isActive ? 1 : 0,
          administrators: 0,
          recentLogins: loggedInRecently ? 1 : 0,
          newAccounts: createdRecently ? 1 : 0,
        },
        recentAccounts: [
          {
            id: user.id,
            username: user.username,
            name: user.name,
            role: user.role,
            createdAt: user.createdAt,
            updatedAt: user.updatedAt,
            lastLoginAt: user.lastLoginAt ?? null,
          },
        ],
        generatedAt: new Date().toISOString(),
      };
    }
    const activeFilter = { status: statusAuthEnum.ACTIVE };
    const [
      activeAccounts,
      administrators,
      recentLogins,
      newAccounts,
      recentAccounts,
    ] = await Promise.all([
      this.accounts.count(activeFilter),
      this.accounts.count({
        ...activeFilter,
        role: roleAuthEnum.ADMINISTRATOR,
      }),
      this.accounts.count({ ...activeFilter, lastLoginSince: thirtyDaysAgo }),
      this.accounts.count({ ...activeFilter, createdSince: thirtyDaysAgo }),
      this.accounts.find(activeFilter, { sort: 'updatedAt', limit: 5 }),
    ]);
    return {
      metrics: { activeAccounts, administrators, recentLogins, newAccounts },
      recentAccounts: recentAccounts.map((user) => ({
        id: user.id,
        username: user.username,
        name: user.name,
        role: user.role,
        createdAt: user.createdAt,
        updatedAt: user.updatedAt,
        lastLoginAt: user.lastLoginAt ?? null,
      })),
      generatedAt: new Date().toISOString(),
    };
  }
  private toPublicUser(user: Account) {
    const id = user.id;
    return {
      id,
      email: user.email,
      username: user.username,
      name: user.name,
      role: user.role,
      status: user.status,
      passwordChangedAt: user.passwordChangedAt ?? null,
      lastLoginAt: user.lastLoginAt ?? null,
      requireReverify: user.requireReverify ?? false,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    };
  }
}
