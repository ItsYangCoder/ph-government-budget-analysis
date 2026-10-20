-- PondoLens | Gold fact_regional_budget
-- Databricks SQL / Delta Lake
-- Grain: one row per year_id, location_id, particular_id.
-- IMPORTANT: Run validation queries first. This script deliberately fails on ambiguous
-- dimension keys or unmatched source records rather than silently dropping them.
-- Confirm source data represents additive detail rows (no totals/subtotals mixed in).
-- Confirm appropriations and obligations are comparable in scope and units.

-- 1. Build standardized staging view. The source columns below match the screenshots.
-- Four historical-name mappings are applied to BOTH Silver inputs before aggregation
-- and the category + particular dimension join. Silver remains unchanged.
-- Check that the mapped names belong to the same category in dim_particular.
CREATE OR REPLACE TEMP VIEW budget_source_standardized AS
WITH a AS (
  SELECT
    CAST(year AS INT) AS year,
    UPPER(TRIM(CAST(region_code AS STRING))) AS region_code,
    UPPER(TRIM(category)) AS category,
    CASE UPPER(TRIM(particular))
      WHEN 'THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
      WHEN 'PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
      WHEN 'OFFICE OF THE PRESS SECRETARY' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
      WHEN 'DEBT SERVICE FUND-INTEREST PAYMENT' THEN 'DEBT INTEREST PAYMENTS'
      ELSE UPPER(TRIM(particular))
    END AS particular,
    TRY_CAST(appropriation_amount AS DECIMAL(20,4)) AS amount,
    CASE WHEN appropriation_amount IS NOT NULL
              AND TRY_CAST(appropriation_amount AS DECIMAL(20,4)) IS NULL
         THEN 1 ELSE 0 END AS invalid_numeric
  FROM pondolens.dev_silver.regional_appropriations
),
o AS (
  SELECT
    CAST(year AS INT) AS year,
    UPPER(TRIM(CAST(region_code AS STRING))) AS region_code,
    UPPER(TRIM(category)) AS category,
    CASE UPPER(TRIM(particular))
      WHEN 'THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
      WHEN 'PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
      WHEN 'OFFICE OF THE PRESS SECRETARY' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
      WHEN 'DEBT SERVICE FUND-INTEREST PAYMENT' THEN 'DEBT INTEREST PAYMENTS'
      ELSE UPPER(TRIM(particular))
    END AS particular,
    TRY_CAST(expenditure_amount AS DECIMAL(20,4)) AS amount,
    CASE WHEN expenditure_amount IS NOT NULL
              AND TRY_CAST(expenditure_amount AS DECIMAL(20,4)) IS NULL
         THEN 1 ELSE 0 END AS invalid_numeric,
    UPPER(TRIM(COALESCE(value_status, ''))) AS value_status
  FROM pondolens.dev_silver.regional_obligations
),
agg_a AS (
  SELECT year, region_code, category, particular,
         SUM(amount) AS appropriation_amount,
         COUNT(*) AS source_rows,
         COUNT(amount) AS valid_rows,
         SUM(invalid_numeric) AS invalid_numeric_rows
  FROM a GROUP BY year, region_code, category, particular
),
agg_o AS (
  SELECT year, region_code, category, particular,
         SUM(amount) AS obligation_amount,
         COUNT(*) AS source_rows,
         COUNT(amount) AS valid_rows,
         SUM(invalid_numeric) AS invalid_numeric_rows,
         COUNT_IF(value_status NOT IN ('', 'REPORTED', 'VALID', 'ACTUAL', 'FINAL', 'REPORTED_ZERO', 'MISSING', 'NOT_REPORTED', 'NULL', 'NOT_AVAILABLE')) AS other_status_rows
  FROM o GROUP BY year, region_code, category, particular
)
SELECT COALESCE(a.year,o.year) AS year,
       COALESCE(a.region_code,o.region_code) AS region_code,
       COALESCE(a.category,o.category) AS category,
       COALESCE(a.particular,o.particular) AS particular,
       a.appropriation_amount,
       CASE
         WHEN a.source_rows IS NULL THEN 'NOT_REPORTED'
         WHEN a.valid_rows = 0 THEN 'MISSING_VALUE'
         WHEN a.valid_rows < a.source_rows THEN 'PARTIALLY_REPORTED'
         WHEN a.appropriation_amount = 0 THEN 'REPORTED_ZERO'
         ELSE 'REPORTED'
       END AS appropriation_value_status,
       o.obligation_amount,
       CASE
         WHEN o.source_rows IS NULL THEN 'NOT_REPORTED'
         WHEN o.valid_rows = 0 THEN 'MISSING_VALUE'
         WHEN o.valid_rows < o.source_rows THEN 'PARTIALLY_REPORTED'
         WHEN o.other_status_rows > 0 THEN 'REVIEW_SOURCE_STATUS'
         WHEN o.obligation_amount = 0 THEN 'REPORTED_ZERO'
         ELSE 'REPORTED'
       END AS obligation_value_status,
       a.source_rows AS appropriation_source_rows,
       o.source_rows AS obligation_source_rows,
       a.valid_rows AS valid_appropriation_rows,
       a.invalid_numeric_rows AS invalid_appropriation_numeric_rows,
       o.invalid_numeric_rows AS invalid_obligation_numeric_rows
FROM agg_a a
FULL OUTER JOIN agg_o o
  ON a.year = o.year
 AND a.region_code = o.region_code
 AND a.category = o.category
 AND a.particular = o.particular;

-- 2. Inspect source coverage and quality BEFORE loading.
SELECT year, COUNT(*) AS grain_rows,
       COUNT_IF(year IS NULL OR region_code IS NULL OR region_code = ''
                OR category IS NULL OR category = ''
                OR particular IS NULL OR particular = '') AS invalid_keys,
       COUNT_IF(appropriation_source_rows > 0 AND valid_appropriation_rows < appropriation_source_rows) AS missing_or_partial_appropriations,
       SUM(COALESCE(invalid_appropriation_numeric_rows, 0)) AS malformed_appropriation_values,
       SUM(COALESCE(invalid_obligation_numeric_rows, 0)) AS malformed_obligation_values,
       COUNT_IF(obligation_value_status IN ('MISSING_VALUE','PARTIALLY_REPORTED','REVIEW_SOURCE_STATUS')) AS obligations_to_review
FROM budget_source_standardized GROUP BY year ORDER BY year;

-- 3. Map natural keys to dimensions.
-- Location matching is by location_code; check that codes uniquely identify a location
-- across geographic levels. If not, add a verified geographic-level mapping first.
CREATE OR REPLACE TEMP VIEW budget_mapped AS
SELECT s.*,
       dy.year_id,
       dl.location_id,
       dp.particular_id
FROM budget_source_standardized s
LEFT JOIN pondolens.dev_gold.dim_year dy ON s.year = dy.year
LEFT JOIN pondolens.dev_gold.dim_location dl
  ON s.region_code = UPPER(TRIM(CAST(dl.location_code AS STRING)))
LEFT JOIN pondolens.dev_gold.dim_particular dp
  ON s.category = UPPER(TRIM(dp.category))
 AND s.particular = UPPER(TRIM(dp.particular));

-- 4. Diagnostics: must be zero rows before creating the fact.
SELECT year, region_code, category, particular,
       COUNT(*) AS mapped_rows,
       COUNT(DISTINCT year_id) AS year_matches,
       COUNT(DISTINCT location_id) AS location_matches,
       COUNT(DISTINCT particular_id) AS particular_matches
FROM budget_mapped
GROUP BY year, region_code, category, particular
HAVING COUNT(*) <> 1 OR COUNT(year_id) <> 1
    OR COUNT(location_id) <> 1 OR COUNT(particular_id) <> 1;

-- 5. Fail the build when source keys are invalid, dimensions are unmatched/ambiguous,
-- or NON-NULL monetary values cannot be parsed. Genuine NULLs are allowed. Assertions work in Databricks SQL.
SELECT assert_true(
  COUNT_IF(year IS NULL OR region_code IS NULL OR region_code = ''
           OR category IS NULL OR category = ''
           OR particular IS NULL OR particular = ''
           OR year_id IS NULL OR location_id IS NULL OR particular_id IS NULL
           OR COALESCE(invalid_appropriation_numeric_rows, 0) > 0
           OR COALESCE(invalid_obligation_numeric_rows, 0) > 0) = 0,
  'Budget fact load stopped: invalid source values or unmatched dimension keys'
) AS source_key_check
FROM budget_mapped;

SELECT assert_true(
  COUNT(*) = COUNT(DISTINCT named_struct('y', year, 'l', region_code, 'c', category, 'p', particular)),
  'Budget fact load stopped: dimension join multiplied source rows'
) AS unique_source_grain_check
FROM budget_mapped;

SELECT assert_true(
  COUNT(*) = COUNT(DISTINCT named_struct('y', year_id, 'l', location_id, 'p', particular_id)),
  'Budget fact load stopped: duplicate fact foreign-key grain'
) AS unique_fact_grain_check
FROM budget_mapped;

-- 6. Create Delta fact. Stable ID is deterministic for a fixed set of dimension IDs;
-- it will remain stable on rebuilds only if dimension IDs do not change.
-- xxhash64 is not collision-proof: enforce uniqueness with the check below.
CREATE OR REPLACE TABLE pondolens.dev_gold.fact_regional_budget
USING DELTA
AS
SELECT
  xxhash64(year_id, location_id, particular_id) AS regional_budget_id,
  CAST(year_id AS INT) AS year_id,
  CAST(location_id AS INT) AS location_id,
  CAST(particular_id AS INT) AS particular_id,
  CAST(appropriation_amount AS DECIMAL(20,4)) AS appropriation_amount,
  appropriation_value_status,
  CAST(obligation_amount AS DECIMAL(20,4)) AS obligation_amount,
  obligation_value_status,
  CURRENT_TIMESTAMP() AS processed_at
FROM budget_mapped;

-- 7. Post-load uniqueness and integrity checks.
SELECT regional_budget_id, COUNT(*) AS row_count
FROM pondolens.dev_gold.fact_regional_budget
GROUP BY regional_budget_id HAVING COUNT(*) > 1;

SELECT year_id, location_id, particular_id, COUNT(*) AS row_count
FROM pondolens.dev_gold.fact_regional_budget
GROUP BY year_id, location_id, particular_id HAVING COUNT(*) > 1;

-- 8. Yearly totals for reconciliation with DETAIL-only source totals.
SELECT y.year, COUNT(*) AS fact_rows,
       SUM(f.appropriation_amount) AS total_appropriations,
       SUM(f.obligation_amount) AS total_obligations,
       COUNT_IF(f.obligation_amount IS NULL) AS missing_obligation_rows,
       COUNT_IF(f.appropriation_amount IS NULL) AS missing_appropriation_rows
FROM pondolens.dev_gold.fact_regional_budget f
JOIN pondolens.dev_gold.dim_year y ON f.year_id = y.year_id
GROUP BY y.year ORDER BY y.year;

-- Production notes:
-- * Review source totals/subtotals and obligations location_type before running;
--   the provided dimension screenshot does not define a safe location_type crosswalk.
-- * value_status vocabulary is not yet confirmed; review REVIEW_SOURCE_STATUS rows.
-- * xxhash64 has a theoretical collision risk; use a persisted identity/key map if
--   externally referenced IDs must have guaranteed collision-free stability.
-- * The 126 verified 2021 Special Purpose Fund appropriation NULLs are permitted.
--   They remain NULL and receive MISSING_VALUE (or PARTIALLY_REPORTED when mixed).
-- * This script is a full refresh, not an incremental MERGE.
