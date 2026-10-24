BEGIN;
CREATE SCHEMA IF NOT EXISTS assets;
CREATE TABLE assets.assets (
  id uuid PRIMARY KEY,
  owner_id varchar(24) NOT NULL REFERENCES auth.accounts(id),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 120),
  category text NOT NULL CHECK (length(btrim(category)) BETWEEN 1 AND 64),
  serial text NOT NULL DEFAULT '' CHECK (length(serial) <= 120),
  status text NOT NULL CHECK (status IN ('in_use','stored','repair','retired')),
  notes text NOT NULL DEFAULT '' CHECK (length(notes) <= 2000),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX assets_owner_updated_idx ON assets.assets (owner_id,updated_at DESC,id DESC);
COMMIT;
