import { SetMetadata } from '@nestjs/common';
import { roleAuthEnum } from '../enums/role-auth.enum';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: roleAuthEnum[]) =>
  SetMetadata(ROLES_KEY, roles);
