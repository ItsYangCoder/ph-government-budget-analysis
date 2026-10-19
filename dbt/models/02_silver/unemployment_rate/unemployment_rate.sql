-- PondoLens | Unemployment Rate Bronze -> Silver | Databricks SQL
-- Initial ID: 3,000,000
-- Run sequentially in one SQL session, with a single writer and a complete Bronze batch.
CREATE SCHEMA IF NOT EXISTS pondolens.dev_silver;

CREATE TABLE IF NOT EXISTS pondolens.dev_silver.unemployment_rate (
  unemployment_rate_id INT, year INT, region_code STRING, region_name STRING,
  unemployment_rate DECIMAL(12,4), run_id STRING, source STRING, processed_at TIMESTAMP
) USING DELTA;

-- Canonical distinct uppercase region codes and names (population pipeline pattern).
CREATE OR REPLACE TEMP VIEW unemployment_region_map AS
SELECT DISTINCT
  UPPER(TRIM(region_code)) AS region_code,
  UPPER(TRIM(region_name)) AS region_name
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL;

SELECT assert_true(COUNT(*) = 0, 'A region code has multiple canonical names')
FROM (
  SELECT region_code FROM unemployment_region_map
  GROUP BY region_code HAVING COUNT(*) > 1
);

-- Include source labels plus canonical aliases; normalize case and punctuation.
CREATE OR REPLACE TEMP VIEW unemployment_region_aliases AS
SELECT DISTINCT
    REGEXP_REPLACE(
        UPPER(TRIM(source_region)),
        '[^A-Z0-9]',
        ''
    ) AS region_key,
    UPPER(TRIM(region_code)) AS region_code,
    UPPER(TRIM(region_name)) AS region_name
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE NULLIF(TRIM(source_region), '') IS NOT NULL
  AND NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL;

CREATE OR REPLACE TEMP VIEW unemployment_stage AS
WITH source AS (
  SELECT
    TRY_CAST(TRY_CAST(TRIM(CAST(year AS STRING)) AS DECIMAL(10,1)) AS INT) AS year,
    TRIM(COALESCE(NULLIF(TRIM(region), ''), geographic_name)) AS source_region,
    TRY_CAST(REGEXP_REPLACE(TRIM(CAST(value AS STRING)), ',', '') AS DECIMAL(12,4)) AS unemployment_rate,
    LOWER(TRIM(estimate_status)) AS estimate_status,
    NULLIF(TRIM(table_version), '') AS table_version,
    LOWER(TRIM(geographic_level)) AS geographic_level,
    LOWER(TRIM(indicator)) AS indicator
  FROM pondolens.dev_bronze.unemployment_rate
), mapped AS (
  SELECT s.*, c.region_code AS region_code,
    c.region_name AS region_name,
    CASE WHEN s.year = 2021 THEN '2021_EXCEPTION'
         WHEN s.year BETWEEN 2022 AND 2024 AND s.estimate_status = 'final' THEN 'SELECTED'
         WHEN s.year = 2025 AND s.estimate_status = 'preliminary' THEN 'SELECTED'
         ELSE 'OTHER_RELEASE' END AS release_selection
  FROM source s
  LEFT JOIN unemployment_region_aliases c
    ON REGEXP_REPLACE(UPPER(TRIM(s.source_region)), '[^A-Z0-9]', '') = c.region_key
), eligible AS (
  SELECT *,
    CASE WHEN geographic_level <> 'region' OR indicator <> 'unemployment rate' THEN 'OUT_OF_SCOPE'
         WHEN year IS NULL OR year NOT BETWEEN 2021 AND 2025 THEN 'INVALID_YEAR'
         WHEN region_code IS NULL OR region_name IS NULL OR region_code = 'PHL' THEN 'UNMAPPED_REGION'
         WHEN unemployment_rate IS NULL OR unemployment_rate NOT BETWEEN 0 AND 100 THEN 'INVALID_RATE'
         WHEN table_version IS NULL OR estimate_status IS NULL OR estimate_status = '' THEN 'MISSING_RELEASE_METADATA'
         WHEN release_selection = 'OTHER_RELEASE' THEN 'SUPERSEDED_RELEASE'
    END AS issue
  FROM mapped
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY year, region_code ORDER BY table_version DESC, estimate_status DESC
  ) AS rn
  FROM eligible WHERE issue IS NULL
)
SELECT year, region_code, region_name, unemployment_rate,
       'pondolens.dev_bronze.unemployment_rate' AS source
FROM ranked WHERE rn = 1;

-- Validate *all* in-scope source rows, not just selected rows; reject unmapped geography.
CREATE OR REPLACE TEMP VIEW unemployment_issues AS
WITH normalized AS (
  SELECT TRY_CAST(TRY_CAST(TRIM(CAST(year AS STRING)) AS DECIMAL(10,1)) AS INT) AS year,
         TRIM(COALESCE(NULLIF(TRIM(region), ''), geographic_name)) AS source_region,
         TRY_CAST(REGEXP_REPLACE(TRIM(CAST(value AS STRING)), ',', '') AS DECIMAL(12,4)) AS rate,
         LOWER(TRIM(estimate_status)) AS status, NULLIF(TRIM(table_version), '') AS version
  FROM pondolens.dev_bronze.unemployment_rate
  WHERE LOWER(TRIM(geographic_level)) = 'region'
    AND LOWER(TRIM(indicator)) = 'unemployment rate'
), mapped AS (
  SELECT n.*, c.region_code, c.region_name,
         CASE WHEN year = 2021 THEN TRUE
              WHEN year BETWEEN 2022 AND 2024 THEN status = 'final'
              WHEN year = 2025 THEN status = 'preliminary'
              ELSE FALSE END AS selected
  FROM normalized n LEFT JOIN unemployment_region_aliases c
    ON REGEXP_REPLACE(UPPER(TRIM(n.source_region)), '[^A-Z0-9]', '') = c.region_key
)
SELECT *, CASE
  WHEN year IS NULL OR year NOT BETWEEN 2021 AND 2025 THEN 'INVALID_YEAR'
  WHEN region_code IS NULL OR region_name IS NULL OR region_code = 'PHL' THEN 'UNMAPPED_REGION'
  WHEN rate IS NULL OR rate NOT BETWEEN 0 AND 100 THEN 'INVALID_RATE'
  WHEN version IS NULL OR status IS NULL OR status = '' THEN 'MISSING_RELEASE_METADATA'
END AS issue
FROM mapped;

SELECT assert_true(
  (SELECT COUNT(*) FROM unemployment_issues) > 0
  AND (SELECT COUNT(*) FROM unemployment_stage) > 0
  AND (SELECT COUNT(*) FROM unemployment_issues WHERE issue IS NOT NULL) = 0
  AND (SELECT COUNT(*) FROM (
    SELECT year, region_code FROM unemployment_issues WHERE selected
    GROUP BY year, region_code
    HAVING COUNT(DISTINCT CONCAT_WS('|', version, status, CAST(rate AS STRING))) > 1
  )) = 0
  AND (SELECT COUNT(*) FROM (
    SELECT year, region_code FROM unemployment_stage GROUP BY year, region_code HAVING COUNT(*) > 1
  )) = 0
  AND (SELECT COUNT(*) FROM pondolens.dev_silver.unemployment_rate
       WHERE year IS NULL OR region_code IS NULL OR unemployment_rate_id IS NULL OR unemployment_rate_id < 3000000) = 0
  AND (SELECT COUNT(*) FROM (
    SELECT year, UPPER(REGEXP_REPLACE(TRIM(region_code), '[^A-Za-z0-9]', '')) AS code
    FROM pondolens.dev_silver.unemployment_rate GROUP BY 1, 2 HAVING COUNT(*) > 1
  )) = 0
  AND (SELECT COUNT(*) FROM (
    SELECT unemployment_rate_id FROM pondolens.dev_silver.unemployment_rate
    GROUP BY 1 HAVING COUNT(*) > 1
  )) = 0,
  'Unemployment validation failed: review source mapping, rates, release conflicts or target keys'
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