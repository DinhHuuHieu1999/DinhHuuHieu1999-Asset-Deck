import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

export class ResetPasswordDto {
  @ApiProperty({
    example: '4b8e45cb-2f0b-4f97-a7b4-b5caef6f2e0f',
    description: 'Password reset token issued by forgot-password flow',
  })
  @IsString()
  token!: string;

  @ApiProperty({ example: 'NewP@ssw0rd123', minLength: 8, maxLength: 72 })
  @IsString()
  @MinLength(8)
  @MaxLength(72)
  newPassword!: string;
}
