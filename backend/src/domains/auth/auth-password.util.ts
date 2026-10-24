import { BadRequestException } from '@nestjs/common';

/** Rejects password changes that would keep the current password unchanged. */
export function ensurePasswordChanged(
  currentPassword: string,
  newPassword: string,
): void {
  if (newPassword === currentPassword) {
    throw new BadRequestException(
      'New password must be different from current password',
    );
  }
}
