import { BadRequestException } from '@nestjs/common';
import { ensurePasswordChanged } from './auth-password.util';

describe('ensurePasswordChanged', () => {
  it('rejects reusing the current password', () => {
    expect(() => {
      ensurePasswordChanged('SamePassword123', 'SamePassword123');
    }).toThrow(
      new BadRequestException(
        'New password must be different from current password',
      ),
    );
  });

  it('accepts a different password', () => {
    expect(() => {
      ensurePasswordChanged('CurrentPassword123', 'NewPassword456');
    }).not.toThrow();
  });
});
