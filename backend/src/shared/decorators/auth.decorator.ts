import { applyDecorators, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../../infrastructure/guards/jwt-auth.guard';
import { RolesGuard } from '../../infrastructure/guards/roles.guard';
import { Roles } from './roles.decorator';
import { roleAuthEnum } from '../enums/role-auth.enum';

export function Auth(...roles: roleAuthEnum[]) {
  return applyDecorators(UseGuards(JwtAuthGuard, RolesGuard), Roles(...roles));
}
