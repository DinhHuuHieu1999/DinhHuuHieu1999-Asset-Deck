-- Source only. Apply separately after backup and explicit rollout approval.
-- Forward-only rollback: disable feature; retain schema and recorded dates.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE assets.assets
  ADD COLUMN last_checked_on date,
  ADD CONSTRAINT assets_last_checked_calendar CHECK (
    last_checked_on IS NULL OR
    last_checked_on BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'
  );
COMMIT;
