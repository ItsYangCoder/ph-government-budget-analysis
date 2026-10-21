-- PondoLens | GRDP per capita Silver data quality report (READ ONLY)
-- Databricks SQL. No CREATE, INSERT, UPDATE, MERGE, DELETE or ASSERT.
-- Price basis: 2018 = constant 2018 prices; year = current prices.
-- National records: region_code PHL, geographic_level national.

WITH base AS (
  SELECT grdp_per_capita_id, UPPER(TRIM(region_code)) AS region_code,
         UPPER(TRIM(region_name)) AS region_name, year,
         grdp_per_capita, price_basis, LOWER(TRIM(geographic_level)) AS geographic_level,
         processing_run_id, processed_at
  FROM pondolens.dev_silver.grdp_per_capita
),
canonical AS (
  SELECT UPPER(TRIM(region_code)) AS region_code,
         COUNT(DISTINCT UPPER(TRIM(region_name))) AS distinct_names,
         MAX(UPPER(TRIM(region_name))) AS region_name
  FROM pondolens.dev_silver.shared_region_crosswalk
  WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
    AND NULLIF(TRIM(region_name), '') IS NOT NULL
  GROUP BY UPPER(TRIM(region_code))
),
key_counts AS (
  SELECT year, region_code, price_basis, geographic_level, COUNT(*) AS n
  FROM base
  GROUP BY year, region_code, price_basis, geographic_level
),
checks AS (
  SELECT 'grdp_per_capita_id' AS column_name, 'Uniqueness' AS quality_dimension,
         'Null or duplicate surrogate ID' AS check_name,
         COUNT(*) AS total_rows,
         COUNT_IF(grdp_per_capita_id IS NULL) + COALESCE(SUM(CASE WHEN grdp_per_capita_id IS NOT NULL THEN 1 ELSE 0 END), 0)
           - COUNT(DISTINCT grdp_per_capita_id) AS failed_rows,
         'IDs must be present and unique' AS notes
  FROM base
  UNION ALL
  SELECT 'grdp_per_capita_id', 'Validity', 'ID below 100000001', COUNT(*),
         COUNT_IF(grdp_per_capita_id < 100000001), 'New GRDP IDs start at 100000001'
  FROM base
  UNION ALL
  SELECT 'region_code', 'Completeness', 'Missing region code', COUNT(*),
         COUNT_IF(region_code IS NULL OR region_code = ''), 'Includes PHL national code'
  FROM base
  UNION ALL
  SELECT 'region_name', 'Completeness', 'Missing region name', COUNT(*),
         COUNT_IF(region_name IS NULL OR region_name = ''), 'Canonical region names required'
  FROM base
  UNION ALL
  SELECT 'year', 'Validity', 'Year outside 2021-2025', COUNT(*),
         COUNT_IF(year IS NULL OR year NOT BETWEEN 2021 AND 2025), 'Expected reporting years: 2021-2025'
  FROM base
  UNION ALL
  SELECT 'grdp_per_capita', 'Validity', 'Missing or nonpositive GRDP per capita', COUNT(*),
         COUNT_IF(grdp_per_capita IS NULL OR grdp_per_capita <= 0), 'Positive PHP per person expected'
  FROM base
  UNION ALL
  SELECT 'price_basis', 'Validity', 'Invalid price basis for year', COUNT(*),
         COUNT_IF(price_basis IS NULL OR year IS NULL OR price_basis NOT IN (2018, year)),
         '2018 = constant prices; year = current prices'
  FROM base
  UNION ALL
  SELECT 'geographic_level', 'Validity', 'Invalid geographic level', COUNT(*),
         COUNT_IF(geographic_level IS NULL OR geographic_level NOT IN ('region', 'national')),
         'Only region and national are expected'
  FROM base
  UNION ALL
  SELECT 'region_code, geographic_level', 'Consistency', 'Incorrect PHL/national classification', COUNT(*),
         COUNT_IF(region_code = 'PHL' AND (geographic_level IS NULL OR geographic_level <> 'national')
               OR geographic_level = 'national' AND (region_code IS NULL OR region_code <> 'PHL')),
         'PHL must be national; other regions must not be national'
  FROM base
  UNION ALL
  SELECT 'region_code', 'Referential integrity', 'Region code missing from crosswalk', COUNT(*),
         COUNT_IF(c.region_code IS NULL), 'Match standardized codes to shared_region_crosswalk'
  FROM base b LEFT JOIN canonical c ON b.region_code = c.region_code
  UNION ALL
  SELECT 'region_name', 'Consistency', 'Region name differs from crosswalk', COUNT(*),
         COUNT_IF(c.region_code IS NOT NULL AND (b.region_name IS NULL OR b.region_name <> c.region_name)),
         'Compared with canonical uppercase region name'
  FROM base b LEFT JOIN canonical c ON b.region_code = c.region_code
  UNION ALL
  SELECT 'region_code', 'Consistency', 'Conflicting names in crosswalk', COUNT(*),
         COUNT_IF(c.distinct_names > 1), 'Crosswalk must have one canonical name per code'
  FROM base b LEFT JOIN canonical c ON b.region_code = c.region_code
  UNION ALL
  SELECT 'year, region_code, price_basis, geographic_level', 'Uniqueness',
         'Duplicate GRDP business key', (SELECT COUNT(*) FROM base),
         COALESCE(SUM(n - 1), 0), 'One record per year, region, price basis and geographic level'
  FROM key_counts WHERE n > 1
  UNION ALL
  SELECT 'processed_at', 'Completeness', 'Missing processed timestamp', COUNT(*),
         COUNT_IF(processed_at IS NULL), 'Silver processing timestamp should be populated'
  FROM base
),
results AS (
  SELECT 'pondolens.dev_silver.grdp_per_capita' AS table_name,
         column_name, quality_dimension, check_name,
         CAST(total_rows AS BIGINT) AS total_rows,
         CAST(failed_rows AS BIGINT) AS failed_rows,
         CAST(CASE WHEN total_rows = 0 THEN NULL ELSE ROUND(100.0 * failed_rows / total_rows, 2) END AS DECIMAL(8,2)) AS failure_percentage,
         CASE WHEN total_rows = 0 THEN 'WARN' WHEN failed_rows > 0 THEN 'FAIL' ELSE 'PASS' END AS status,
         CAST(0 AS DECIMAL(8,2)) AS threshold,
         CURRENT_TIMESTAMP() AS check_timestamp,
         notes
  FROM checks
)
SELECT * FROM results ORDER BY
  CASE status WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END,
  quality_dimension, check_name;

-- OPTIONAL READ-ONLY COVERAGE REPORT: region and price-basis counts by year.
SELECT year, price_basis, geographic_level,
       COUNT(*) AS rows_count,
       COUNT(DISTINCT UPPER(TRIM(region_code))) AS distinct_regions
FROM pondolens.dev_silver.grdp_per_capita
GROUP BY year, price_basis, geographic_level
ORDER BY year, price_basis, geographic_level;

-- OPTIONAL READ-ONLY COVERAGE MATRIX: regional 2018-price observations.
-- Missing years can reflect historical geographic changes (e.g. NIR).
WITH region_years AS (
  SELECT UPPER(TRIM(region_code)) AS region_code, year
  FROM pondolens.dev_silver.grdp_per_capita
  WHERE price_basis = 2018 AND LOWER(TRIM(geographic_level)) = 'region'
  GROUP BY UPPER(TRIM(region_code)), year
)
SELECT region_code,
       MAX(CASE WHEN year = 2021 THEN 'YES' ELSE 'NO' END) AS `2021`,
       MAX(CASE WHEN year = 2022 THEN 'YES' ELSE 'NO' END) AS `2022`,
       MAX(CASE WHEN year = 2023 THEN 'YES' ELSE 'NO' END) AS `2023`,
       MAX(CASE WHEN year = 2024 THEN 'YES' ELSE 'NO' END) AS `2024`,
       MAX(CASE WHEN year = 2025 THEN 'YES' ELSE 'NO' END) AS `2025`
FROM region_years
GROUP BY region_code ORDER BY region_code;
