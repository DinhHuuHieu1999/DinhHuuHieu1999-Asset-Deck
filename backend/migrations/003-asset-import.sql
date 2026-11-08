-- Source only. Apply only with separate operator approval after isolated validation.
-- Rollback: disable the import route/module; retain receipts and inserted assets.
-- Dropping receipts would lose replay protection and is not an automatic rollback.
BEGIN;
CREATE TABLE assets.import_receipts (
  owner_id varchar(24) NOT NULL REFERENCES auth.accounts(id),
  request_id uuid NOT NULL,
  digest text NOT NULL CHECK (digest ~ '^[0-9a-f]{64}$'),
  record_ids uuid[] NOT NULL CHECK (
    cardinality(record_ids) BETWEEN 1 AND 500
    AND array_ndims(record_ids) = 1
    AND array_lower(record_ids, 1) = 1
    AND array_position(record_ids, NULL) IS NULL
  ),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (owner_id, request_id)
);
COMMIT;
