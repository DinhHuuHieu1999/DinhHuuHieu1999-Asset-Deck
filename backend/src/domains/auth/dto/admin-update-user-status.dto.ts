import { ApiProperty } from '@nestjs/swagger';
import { statusAuthEnum } from '../../../shared/enums/status-auth.enum';
import { IsIn } from 'class-validator';
import {
  ACCOUNT_STATUSES,
  type AccountStatus,
} from '../constants/account-statuses';

export class AdminUpdateUserStatusDto {
  @ApiProperty({ enum: ACCOUNT_STATUSES, example: statusAuthEnum.INACTIVE })
  @IsIn(ACCOUNT_STATUSES)
  status!: AccountStatus;
}
