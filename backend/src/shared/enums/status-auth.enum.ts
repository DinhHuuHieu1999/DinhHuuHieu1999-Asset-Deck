/** Account and workflow statuses used by the backend persistence model. */
export const statusAuthEnum = {
  ACTIVE: 'ACTIVE',
  APPROVED: 'APPROVED',
  ARCHIVED: 'ARCHIVED',
  COMPLETED: 'COMPLETED',
  DELETED: 'DELETED',
  DRAFT: 'DRAFT',
  FAILED: 'FAILED',
  INACTIVE: 'INACTIVE',
  PENDING: 'PENDING',
  PROCESSING: 'PROCESSING',
  REJECTED: 'REJECTED',
  SUSPENDED: 'SUSPENDED',
} as const;

export type statusAuthEnum =
  (typeof statusAuthEnum)[keyof typeof statusAuthEnum];
