BEGIN;
ALTER TABLE assets.assets
  ADD COLUMN purchased_on date,
  ADD COLUMN warranty_expires_on date,
  ADD CONSTRAINT assets_purchase_date_range CHECK
    (purchased_on IS NULL OR purchased_on BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'),
  ADD CONSTRAINT assets_warranty_date_range CHECK
    (warranty_expires_on IS NULL OR warranty_expires_on BETWEEN DATE '0001-01-01' AND DATE '9999-12-31'),
  ADD CONSTRAINT assets_warranty_date_order CHECK
    (purchased_on IS NULL OR warranty_expires_on IS NULL OR warranty_expires_on >= purchased_on);
COMMIT;
