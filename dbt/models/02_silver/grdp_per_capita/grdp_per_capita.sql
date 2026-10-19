-- PondoLens GRDP per capita: Bronze -> Silver (2021-2025)
-- grdp_per_capita id starts at 100,000,000
-- Run as one Databricks SQL session; configure job max concurrent runs = 1.
SET TIME ZONE 'UTC';

DROP TABLE IF EXISTS pondolens.dev_silver.grdp_per_capita;

CREATE TABLE IF NOT EXISTS pondolens.dev_silver.grdp_per_capita (
  grdp_per_capita_id INT, region_code STRING, region_name STRING,
  year INT, grdp_per_capita BIGINT, price_basis INT,
  geographic_level STRING, processing_run_id STRING, processed_at TIMESTAMP
) USING DELTA;

-- Canonical geography: preserve national row; exclude central office.
CREATE OR REPLACE TEMP VIEW grdp_region_map AS
SELECT DISTINCT UPPER(TRIM(region_code)) AS region_code,
  UPPER(TRIM(region_name)) AS region_name,
  CASE WHEN UPPER(TRIM(region_code)) = 'PHL' THEN 'national' ELSE 'region' END AS geographic_level
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL
  AND UPPER(TRIM(region_code)) <> 'CO';

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Crosswalk has conflicting canonical region names')
FROM (SELECT region_code FROM grdp_region_map GROUP BY region_code HAVING COUNT(*) > 1);

-- Use real source aliases plus canonical names and codes; do not synthesize ambiguous aliases.
CREATE OR REPLACE TEMP VIEW grdp_region_aliases AS
WITH labels AS (
  SELECT UPPER(TRIM(region_code)) AS region_code,
    REGEXP_REPLACE(UPPER(TRIM(source_region)), '[^A-Z0-9]', '') AS region_key
  FROM pondolens.dev_silver.shared_region_crosswalk
  UNION ALL
  SELECT region_code, REGEXP_REPLACE(region_name, '[^A-Z0-9]', '') FROM grdp_region_map
  UNION ALL
  SELECT region_code, REGEXP_REPLACE(region_code, '[^A-Z0-9]', '') FROM grdp_region_map
)
SELECT DISTINCT region_key, region_code FROM labels WHERE region_key <> '';

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Normalized GRDP region alias maps to multiple codes')
FROM (SELECT region_key FROM grdp_region_aliases GROUP BY region_key HAVING COUNT(*) > 1);

-- Parse all source rows in scope, including both price bases.
-- Keep current-price rows in Silver; filter price_basis = 2018 in Gold.
CREATE OR REPLACE TEMP VIEW grdp_pc_prepared AS
SELECT
  NULLIF(REGEXP_REPLACE(UPPER(TRIM(region_id)), '[^A-Z0-9]', ''), '') AS code_key,
  NULLIF(REGEXP_REPLACE(UPPER(TRIM(region)), '[^A-Z0-9]', ''), '') AS name_key,
  TRY_CAST(year AS INT) AS year,
  TRY_CAST(ROUND(TRY_CAST(REPLACE(TRIM(GRDP_per_capita_amount), ',', '') AS DECIMAL(30,15)), 0) AS BIGINT) AS grdp_per_capita,
  LOWER(TRIM(price_basis)) AS source_price_basis,
  LOWER(TRIM(geographic_level)) AS source_geographic_level,
  _rescued_data
FROM pondolens.dev_bronze.grdp_per_capita
WHERE TRY_CAST(year AS INT) BETWEEN 2021 AND 2025;

-- Resolve by source code/name, with an explicit national Philippines mapping.
-- The source uses 'country'; Silver standardizes this to 'national'.
CREATE OR REPLACE TEMP VIEW grdp_pc_stage AS
WITH resolved AS (
  SELECT p.*,
    mc.region_code AS code_match,
    mn.region_code AS name_match,
    CASE
      WHEN p.source_geographic_level = 'country' AND p.name_key = 'PHILIPPINES'
        THEN 'PHL'
      ELSE COALESCE(mc.region_code, mn.region_code)
    END AS mapped_code
  FROM grdp_pc_prepared p
  LEFT JOIN grdp_region_aliases mc ON p.code_key = mc.region_key
  LEFT JOIN grdp_region_aliases mn ON p.name_key = mn.region_key
)
SELECT
  r.mapped_code AS region_code,
  CASE
    WHEN r.source_geographic_level = 'country' AND r.name_key = 'PHILIPPINES'
      THEN 'PHILIPPINES'
    ELSE m.region_name
  END AS region_name,
  r.year,
  r.grdp_per_capita,
  CASE
    WHEN r.source_price_basis = 'at constant 2018 prices' THEN 2018
    WHEN r.source_price_basis = 'at current prices' THEN r.year
  END AS price_basis,
  m.geographic_level,
  r.code_match, r.name_match, r.code_key, r.name_key,
  r.source_price_basis, r.source_geographic_level, r._rescued_data
FROM resolved r
LEFT JOIN grdp_region_map m ON r.mapped_code = m.region_code;

SELECT ASSERT_TRUE(COUNT(*) > 0, 'No GRDP records in 2021-2025 scope') FROM grdp_pc_stage;
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Invalid GRDP source rows, crosswalk mapping, or price basis')
FROM grdp_pc_stage
WHERE region_code IS NULL OR region_name IS NULL OR year IS NULL
  OR grdp_per_capita IS NULL OR grdp_per_capita <= 0
  OR price_basis IS NULL OR price_basis NOT IN (2018, year)
  OR (code_match IS NOT NULL AND name_match IS NOT NULL AND code_match <> name_match)
  OR (source_geographic_level = 'country' AND code_match IS NOT NULL AND code_match <> 'PHL')
  OR (source_geographic_level = 'country' AND name_match IS NOT NULL AND name_match <> 'PHL')
  OR source_geographic_level NOT IN ('region', 'country')
  OR (source_geographic_level = 'region' AND geographic_level <> 'region')
  OR (source_geographic_level = 'country' AND (geographic_level <> 'national' OR region_code <> 'PHL' OR name_key <> 'PHILIPPINES'))
  OR NULLIF(TRIM(_rescued_data), '') IS NOT NULL;

SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT STRUCT(year, region_code, price_basis, geographic_level)),
  'Duplicate GRDP source business keys') FROM grdp_pc_stage;

SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT grdp_per_capita_id)
  AND COUNT(*) = COUNT(DISTINCT STRUCT(year, UPPER(REPLACE(TRIM(region_code), '-', '')), price_basis, geographic_level))
  AND COUNT_IF(grdp_per_capita_id IS NULL OR grdp_per_capita_id < 100000001) = 0,
  'Invalid existing GRDP Silver IDs or business keys')
FROM pondolens.dev_silver.grdp_per_capita;

-- Guard against accidentally replacing a complete year with a partial load.
SELECT ASSERT_TRUE(COUNT(*) = 0, 'GRDP stage has fewer than 80% of existing Silver rows for a year')
FROM (
  SELECT t.year, COUNT(*) AS old_rows, MAX(s.n) AS new_rows
  FROM pondolens.dev_silver.grdp_per_capita t
  JOIN (SELECT year, COUNT(*) n FROM grdp_pc_stage GROUP BY year) s ON t.year = s.year
  GROUP BY t.year
  HAVING MAX(s.n) < 0.8 * COUNT(*)
);

CREATE OR REPLACE TEMP VIEW grdp_pc_numbered AS
WITH new_rows AS (
  SELECT s.region_code, s.year, s.price_basis, s.geographic_level
  FROM grdp_pc_stage s
  LEFT ANTI JOIN pondolens.dev_silver.grdp_per_capita t
    ON s.year = t.year AND s.region_code = UPPER(REPLACE(TRIM(t.region_code), '-', ''))
    AND s.price_basis = t.price_basis AND s.geographic_level = t.geographic_level
), last_id AS (
  SELECT GREATEST(COALESCE(MAX(CAST(grdp_per_capita_id AS BIGINT)), 100000000), 100000000) AS last_number
  FROM pondolens.dev_silver.grdp_per_capita
)
SELECT n.*, l.last_number + ROW_NUMBER() OVER
  (ORDER BY n.year, n.region_code, n.price_basis, n.geographic_level) AS new_id
FROM new_rows n CROSS JOIN last_id l;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'GRDP ID exceeds INT range')
FROM grdp_pc_numbered WHERE new_id > 2147483647;

-- Include deletions only for years present in the validated source.
CREATE OR REPLACE TEMP VIEW grdp_pc_merge_source AS
WITH source_rows AS (
  SELECT COALESCE(t.grdp_per_capita_id, CAST(n.new_id AS INT)) AS grdp_per_capita_id,
    s.region_code, s.region_name, s.year, s.grdp_per_capita, s.price_basis,
    s.geographic_level, FALSE AS removed
  FROM grdp_pc_stage s
  LEFT JOIN pondolens.dev_silver.grdp_per_capita t
    ON s.year = t.year AND s.region_code = UPPER(REPLACE(TRIM(t.region_code), '-', ''))
    AND s.price_basis = t.price_basis AND s.geographic_level = t.geographic_level
  LEFT JOIN grdp_pc_numbered n
    ON s.year = n.year AND s.region_code = n.region_code
    AND s.price_basis = n.price_basis AND s.geographic_level = n.geographic_level
), deleted_rows AS (
  SELECT t.grdp_per_capita_id, t.region_code, t.region_name, t.year,
    t.grdp_per_capita, t.price_basis, t.geographic_level, TRUE AS removed
  FROM pondolens.dev_silver.grdp_per_capita t
  LEFT SEMI JOIN (SELECT DISTINCT year FROM grdp_pc_stage) y ON t.year = y.year
  LEFT ANTI JOIN grdp_pc_stage s
    ON t.year = s.year AND UPPER(REPLACE(TRIM(t.region_code), '-', '')) = s.region_code
    AND t.price_basis = s.price_basis AND t.geographic_level = s.geographic_level
)
SELECT * FROM source_rows UNION ALL SELECT * FROM deleted_rows;

MERGE INTO pondolens.dev_silver.grdp_per_capita t
USING grdp_pc_merge_source s ON t.grdp_per_capita_id = s.grdp_per_capita_id
WHEN MATCHED AND s.removed THEN DELETE
WHEN MATCHED AND NOT s.removed AND NOT (
  t.region_code <=> s.region_code AND t.region_name <=> s.region_name
  AND t.grdp_per_capita <=> s.grdp_per_capita
) THEN UPDATE SET
  t.region_code = s.region_code, t.region_name = s.region_name,
  t.grdp_per_capita = s.grdp_per_capita,
  t.processing_run_id = CONCAT('silver_grdp_pc_', DATE_FORMAT(CURRENT_TIMESTAMP(), 'yyyyMMddHHmmss')),
  t.processed_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND NOT s.removed THEN INSERT
  (grdp_per_capita_id, region_code, region_name, year, grdp_per_capita,
   price_basis, geographic_level, processing_run_id, processed_at)
VALUES (s.grdp_per_capita_id, s.region_code, s.region_name, s.year,
  s.grdp_per_capita, s.price_basis, s.geographic_level,
  CONCAT('silver_grdp_pc_', DATE_FORMAT(CURRENT_TIMESTAMP(), 'yyyyMMddHHmmss')),
  CURRENT_TIMESTAMP());

-- Compare multisets to detect missing, extra, or changed records (including duplicates).
CREATE OR REPLACE TEMP VIEW grdp_pc_differences AS
WITH expected AS (
  SELECT region_code, region_name, year, grdp_per_capita, price_basis, geographic_level
  FROM grdp_pc_stage
), actual AS (
  SELECT region_code, region_name, year, grdp_per_capita, price_basis, geographic_level
  FROM pondolens.dev_silver.grdp_per_capita WHERE year BETWEEN 2021 AND 2025
)
SELECT * FROM (SELECT * FROM expected EXCEPT ALL SELECT * FROM actual)
UNION ALL
SELECT * FROM (SELECT * FROM actual EXCEPT ALL SELECT * FROM expected);

SELECT ASSERT_TRUE(COUNT(*) = 0, 'GRDP Silver differs from validated stage') FROM grdp_pc_differences;
SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT grdp_per_capita_id), 'Duplicate GRDP Silver IDs')
FROM pondolens.dev_silver.grdp_per_capita;
SELECT year, price_basis, COUNT(*) AS records FROM pondolens.dev_silver.grdp_per_capita
GROUP BY year, price_basis ORDER BY year, price_basis;
