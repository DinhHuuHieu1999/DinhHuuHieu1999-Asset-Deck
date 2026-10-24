import { statusAuthEnum } from '../../../shared/enums/status-auth.enum';

export const ACCOUNT_STATUSES = [
  statusAuthEnum.ACTIVE,
  statusAuthEnum.INACTIVE,
  statusAuthEnum.SUSPENDED,
  statusAuthEnum.PENDING,
] as const;

export type AccountStatus = (typeof ACCOUNT_STATUSES)[number];
