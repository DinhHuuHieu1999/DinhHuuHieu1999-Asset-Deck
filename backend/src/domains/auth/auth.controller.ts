import {
  Body,
  Controller,
  Get,
  HttpCode,
  Patch,
  Post,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Auth } from '../../shared/decorators/auth.decorator';
import { Public } from '../../shared/decorators/public.decorator';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { ChangePasswordDto } from './dto/change-password.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';

/** Personal account endpoints; no account directory or administration API. */
@Controller('auth')
export class AuthController {
  constructor(private readonly service: AuthService) {}

  /** Register a personal account through the existing security service. */
  @Public()
  @Post('register')
  register(@Body() input: RegisterDto) {
    return this.service.register(input);
  }

  /** Authenticate with the existing lockout and account-status checks. */
  @Public()
  @UseGuards(AuthGuard('local'))
  @Post('login')
  @HttpCode(200)
  login(@Req() req: { user: { userId: string; email: string; role: string } }) {
    return this.service.loginPassport(
      req.user.userId,
      req.user.email,
      req.user.role,
    );
  }

  /** Read only the authenticated account profile. */
  @Auth()
  @Get('profile')
  profile(@Req() req: { user: { userId: string } }) {
    return this.service.getProfile(req.user.userId);
  }

  /** Change the authenticated account password after verifying its current value. */
  @Auth()
  @Patch('change-password')
  changePassword(
    @Req() req: { user: { userId: string } },
    @Body() input: ChangePasswordDto,
  ) {
    return this.service.changePassword(req.user.userId, input);
  }

  /** Preserve generic reset responses without exposing account existence. */
  @Public()
  @Post('forgot-password')
  @HttpCode(200)
  forgotPassword(@Body() input: ForgotPasswordDto) {
    return this.service.forgotPassword(input);
  }

  /** Validate the existing expiring reset-token contract. */
  @Public()
  @Post('reset-password')
  @HttpCode(200)
  resetPassword(@Body() input: ResetPasswordDto) {
    return this.service.resetPassword(input);
  }
}
