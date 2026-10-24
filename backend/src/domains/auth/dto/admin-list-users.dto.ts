import { ApiPropertyOptional } from '@nestjs/swagger';
import { roleAuthEnum } from '../../../shared/enums/role-auth.enum';
import { Type } from 'class-transformer';
import {
  IsEnum,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import {
  ACCOUNT_STATUSES,
  type AccountStatus,
} from '../constants/account-statuses';

export class AdminListUsersDto {
  @ApiPropertyOptional({ minimum: 1, default: 1 })
  @Type(() => Number)
  @IsOptional()
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ minimum: 1, maximum: 100, default: 20 })
  @Type(() => Number)
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;

  @ApiPropertyOptional({ enum: roleAuthEnum })
  @IsOptional()
  @IsEnum(roleAuthEnum)
  role?: roleAuthEnum;

  @ApiPropertyOptional({ enum: ACCOUNT_STATUSES })
  @IsOptional()
  @IsIn(ACCOUNT_STATUSES)
  status?: AccountStatus;

  @ApiPropertyOptional({ example: 'john' })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;
}
