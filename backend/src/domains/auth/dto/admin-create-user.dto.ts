import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { roleAuthEnum } from '../../../shared/enums/role-auth.enum';
import { statusAuthEnum } from '../../../shared/enums/status-auth.enum';
import {
  IsEmail,
  IsEnum,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import {
  ACCOUNT_STATUSES,
  type AccountStatus,
} from '../constants/account-statuses';

export class AdminCreateUserDto {
  @ApiProperty({ example: 'new.user@example.com' })
  @IsEmail()
  email!: string;

  @ApiProperty({
    example: 'new.user',
    minLength: 3,
    maxLength: 30,
    description: 'Unique username (letters, numbers, underscore, dot)',
  })
  @IsString()
  @MinLength(3)
  @MaxLength(30)
  @Matches(/^[a-z0-9._]+$/i)
  username!: string;

  @ApiProperty({ example: 'New User', maxLength: 100 })
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

  @ApiProperty({ example: 'P@ssw0rd123', minLength: 8, maxLength: 72 })
  @IsString()
  @MinLength(8)
  @MaxLength(72)
  password!: string;

  @ApiPropertyOptional({ enum: roleAuthEnum, default: roleAuthEnum.USER })
  @IsOptional()
  @IsEnum(roleAuthEnum)
  role?: roleAuthEnum;

  @ApiPropertyOptional({
    enum: ACCOUNT_STATUSES,
    default: statusAuthEnum.ACTIVE,
  })
  @IsOptional()
  @IsIn(ACCOUNT_STATUSES)
  status?: AccountStatus;
}
