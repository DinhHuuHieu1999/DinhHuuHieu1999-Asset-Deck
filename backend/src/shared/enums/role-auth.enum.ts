/** Roles enforced by the backend authorization layer. */
export const roleAuthEnum = {
  ADMINISTRATOR: 'ADMINISTRATOR',
  USER: 'USER',
} as const;

export type roleAuthEnum = (typeof roleAuthEnum)[keyof typeof roleAuthEnum];
