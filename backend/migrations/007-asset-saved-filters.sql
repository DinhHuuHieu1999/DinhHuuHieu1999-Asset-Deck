-- Source only: apply separately after backup and rollout approval.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TABLE assets.saved_filters (
  id uuid PRIMARY KEY,
  owner_id varchar(24) NOT NULL REFERENCES auth.accounts(id),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 60),
  query_schema_version integer NOT NULL CHECK (query_schema_version = 1),
  query jsonb NOT NULL CHECK (jsonb_typeof(query) = 'object'),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX saved_filters_owner_idx ON assets.saved_filters(owner_id,id);
COMMIT;
