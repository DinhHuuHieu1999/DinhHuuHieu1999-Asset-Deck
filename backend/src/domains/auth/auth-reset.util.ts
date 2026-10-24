/** Returns whether a raw password-reset token may be exposed for explicit local debugging. */
export function shouldExposeResetToken(
  nodeEnv?: string,
  exposeFlag?: string,
): boolean {
  return nodeEnv !== 'production' && exposeFlag === 'true';
}
