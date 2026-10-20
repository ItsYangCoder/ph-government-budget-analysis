-- PondoLens | Unemployment Rate Bronze -> Silver | Databricks SQL
-- Initial ID: 3,000,000
-- Run sequentially in one SQL session, with a single writer and a complete Bronze batch.
CREATE SCHEMA IF NOT EXISTS pondolens.dev_silver;

CREATE TABLE IF NOT EXISTS pondolens.dev_silver.unemployment_rate (
  unemployment_rate_id INT, year INT, region_code STRING, region_name STRING,
  unemployment_rate DECIMAL(12,4), run_id STRING, source STRING, processed_at TIMESTAMP
) USING DELTA;

-- Assumes crosswalk columns valid_from_year and valid_to_year (inclusive).
-- Change these two names if your crosswalk schema uses different names.
CREATE OR REPLACE TEMP VIEW unemployment_region_aliases AS
SELECT DISTINCT
  REGEXP_REPLACE(UPPER(TRIM(source_region)), '[^A-Z0-9]', '') AS region_key,
  UPPER(REGEXP_REPLACE(TRIM(region_code), '[^A-Z0-9]', '')) AS region_code,
  UPPER(TRIM(region_name)) AS region_name,
  TRY_CAST(valid_from_year AS INT) AS valid_from_year,
  TRY_CAST(valid_to_year AS INT) AS valid_to_year
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE NULLIF(TRIM(source_region), '') IS NOT NULL
  AND NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL;

-- Fail on ambiguous year-specific aliases, not on legitimate historical changes.
SELECT assert_true(COUNT(*) = 0, 'Overlapping crosswalk aliases map to different regions')
FROM unemployment_region_aliases a
JOIN unemployment_region_aliases b
  ON a.region_key = b.region_key
 AND a.region_code <> b.region_code
 AND COALESCE(a.valid_from_year, -9999) <= COALESCE(b.valid_to_year, 9999)
 AND COALESCE(b.valid_from_year, -9999) <= COALESCE(a.valid_to_year, 9999);

-- Normalize every Bronze row before filtering, so invalid scope values are audited.
CREATE OR REPLACE TEMP VIEW unemployment_normalized AS
WITH parsed AS (
  SELECT
    TRIM(CAST(year AS STRING)) AS raw_year,
    TRY_CAST(TRIM(CAST(year AS STRING)) AS DECIMAL(18,6)) AS numeric_year,
    TRIM(COALESCE(NULLIF(TRIM(region), ''), geographic_name)) AS source_region,
    TRY_CAST(REGEXP_REPLACE(TRIM(CAST(value AS STRING)), ',', '') AS DECIMAL(12,4)) AS rate,
    LOWER(TRIM(estimate_status)) AS status,
    NULLIF(TRIM(table_version), '') AS version,
    LOWER(TRIM(geographic_level)) AS geographic_level,
    LOWER(TRIM(indicator)) AS indicator
  FROM pondolens.dev_bronze.unemployment_rate
)
SELECT *,
  CASE WHEN numeric_year IS NOT NULL
             AND numeric_year = FLOOR(numeric_year)
             AND numeric_year BETWEEN 2021 AND 2025
       THEN TRY_CAST(numeric_year AS INT) END AS year
FROM parsed;

-- Join aliases only for the years in which their mapping is valid.
CREATE OR REPLACE TEMP VIEW unemployment_mapped AS
SELECT n.*, c.region_code, c.region_name,
  CASE WHEN n.year = 2021 THEN TRUE
       WHEN n.year BETWEEN 2022 AND 2024 THEN n.status = 'final'
       WHEN n.year = 2025 THEN n.status = 'preliminary'
       ELSE FALSE END AS selected
FROM unemployment_normalized n
LEFT JOIN unemployment_region_aliases c
  ON REGEXP_REPLACE(UPPER(TRIM(n.source_region)), '[^A-Z0-9]', '') = c.region_key
 AND n.year >= COALESCE(c.valid_from_year, -9999)
 AND n.year <= COALESCE(c.valid_to_year, 9999);

CREATE OR REPLACE TEMP VIEW unemployment_issues AS
SELECT *, CASE
  WHEN geographic_level IS NULL OR geographic_level <> 'region'
    OR indicator IS NULL OR indicator <> 'unemployment rate' THEN 'OUT_OF_SCOPE'
  WHEN year IS NULL THEN 'INVALID_YEAR'
  WHEN region_code IS NULL OR region_name IS NULL OR region_code = 'PHL' THEN 'UNMAPPED_REGION'
  WHEN rate IS NULL OR rate NOT BETWEEN 0 AND 100 THEN 'INVALID_RATE'
  WHEN version IS NULL OR status IS NULL OR status = '' THEN 'MISSING_RELEASE_METADATA'
  ELSE NULL END AS issue
FROM unemployment_mapped;

CREATE OR REPLACE TEMP VIEW unemployment_stage AS
WITH ranked AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY year, region_code ORDER BY version DESC, status DESC
  ) AS rn
  FROM unemployment_issues WHERE issue IS NULL AND selected = TRUE
)
SELECT year, region_code, region_name, rate AS unemployment_rate,
       'pondolens.dev_bronze.unemployment_rate' AS source
FROM ranked WHERE rn = 1;

-- Invalid scope rows are excluded from Silver, while invalid in-scope rows block loading.
-- Review rejected scope rows separately; they cannot silently enter staging.
SELECT issue, COUNT(*) AS row_count
FROM unemployment_issues GROUP BY issue ORDER BY issue;

SELECT assert_true(
  (SELECT COUNT(*) FROM unemployment_stage) > 0
  AND (SELECT COUNT(*) FROM unemployment_issues
       WHERE issue IS NOT NULL AND issue <> 'OUT_OF_SCOPE') = 0
  AND (SELECT COUNT(*) FROM (
    SELECT year, region_code FROM unemployment_issues
    WHERE issue IS NULL AND selected = TRUE
    GROUP BY year, region_code
    HAVING COUNT(DISTINCT CONCAT_WS('|', version, status, CAST(rate AS STRING))) > 1
  )) = 0
  AND (SELECT COUNT(*) FROM (
    SELECT year, region_code FROM unemployment_stage
    GROUP BY year, region_code HAVING COUNT(*) > 1
  )) = 0
  AND (SELECT COUNT(*) FROM pondolens.dev_silver.unemployment_rate
       WHERE year IS NULL OR region_code IS NULL OR unemployment_rate_id IS NULL
          OR unemployment_rate_id < 3000000) = 0
  AND (SELECT COUNT(*) FROM (
    SELECT year, UPPER(REGEXP_REPLACE(TRIM(region_code), '[^A-Za-z0-9]', '')) AS code
    FROM pondolens.dev_silver.unemployment_rate
    GROUP BY 1, 2 HAVING COUNT(*) > 1
  )) = 0
  AND (SELECT COUNT(*) FROM (
    SELECT unemployment_rate_id FROM pondolens.dev_silver.unemployment_rate
    GROUP BY 1 HAVING COUNT(*) > 1
  )) = 0,
  'Unemployment validation failed: review rejected rows, mapping, rates or keys'
);

-- Preserve IDs on matching keys; allocate only for newly observed region-year keys.
CREATE OR REPLACE TEMP VIEW unemployment_upsert AS
WITH new_keys AS (
  SELECT s.year, s.region_code,
         ROW_NUMBER() OVER (ORDER BY s.year, s.region_code) AS seq
  FROM unemployment_stage s
  LEFT ANTI JOIN pondolens.dev_silver.unemployment_rate t
    ON s.year = t.year
   AND s.region_code = UPPER(REGEXP_REPLACE(TRIM(t.region_code), '[^A-Za-z0-9]', ''))
), max_id AS (
  SELECT GREATEST(COALESCE(MAX(unemployment_rate_id), 2999999), 2999999) AS id
  FROM pondolens.dev_silver.unemployment_rate
)
SELECT s.*, m.id + n.seq AS new_id
FROM unemployment_stage s
LEFT JOIN new_keys n ON s.year = n.year AND s.region_code = n.region_code
CROSS JOIN max_id m;

SELECT assert_true(COALESCE(MAX(new_id), 0) <= 2147483647, 'Unemployment ID overflow')
FROM unemployment_upsert;

MERGE INTO pondolens.dev_silver.unemployment_rate t
USING unemployment_upsert s
ON t.year = s.year
AND UPPER(REGEXP_REPLACE(TRIM(t.region_code), '[^A-Za-z0-9]', '')) = s.region_code
WHEN MATCHED AND (
  NOT (t.region_code <=> s.region_code) OR
  NOT (t.region_name <=> s.region_name) OR
  NOT (t.unemployment_rate <=> s.unemployment_rate) OR
  NOT (t.source <=> s.source)
) THEN UPDATE SET
  t.region_code = s.region_code, t.region_name = s.region_name,
  t.unemployment_rate = s.unemployment_rate, t.source = s.source,
  t.run_id = CONCAT('unemployment_', DATE_FORMAT(CURRENT_TIMESTAMP(), 'yyyyMMdd_HHmmss')),
  t.processed_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
  unemployment_rate_id, year, region_code, region_name,
  unemployment_rate, run_id, source, processed_at
) VALUES (
  CAST(s.new_id AS INT), s.year, s.region_code, s.region_name,
  s.unemployment_rate,
  CONCAT('unemployment_', DATE_FORMAT(CURRENT_TIMESTAMP(), 'yyyyMMdd_HHmmss')),
  s.source, CURRENT_TIMESTAMP()
);

-- Validate that Silver matches the unemployment stage.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Silver differs from validated unemployment stage'
)
FROM unemployment_stage s
LEFT JOIN pondolens.dev_silver.unemployment_rate t
    ON s.year = t.year
   AND s.region_code = t.region_code
WHERE t.unemployment_rate_id IS NULL
   OR NOT (s.region_name <=> t.region_name)
   OR NOT (s.unemployment_rate <=> t.unemployment_rate);