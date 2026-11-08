BEGIN;
ALTER TABLE assets.assets
  ADD COLUMN location text,
  ADD CONSTRAINT assets_location_label CHECK (
    location IS NULL OR (
      char_length(location) BETWEEN 1 AND 120
      AND location = btrim(location)
      AND location !~ '[[:cntrl:]]'
    )
  );
COMMIT;
