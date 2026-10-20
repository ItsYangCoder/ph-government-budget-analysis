-- Dataset: grdp_per_capita
-- Table: pondolens.dev_bronze.grdp_per_capita
-- Owner: Anjelika Marquez
-- Scope: active
-- Execute the complete file in one Databricks SQL session.
-- Persistent tables are read-only; session TEMP VIEWs are allowed.
-- Evidence and unresolved checks: findings.md. Column definitions: data_dictionary.md.

-- GRDP per capita | Bronze profiling | Assigned to: Anje
-- Run in order in one Databricks SQL session.
-- Reads persistent tables; creates session-scoped temporary views only.
-- Full Bronze coverage is inspected before the 2021-2025 project scope.

-- 1. Structure.
DESCRIBE TABLE pondolens.dev_bronze.grdp_per_capita;
DESCRIBE TABLE pondolens.dev_silver.shared_region_crosswalk;

CREATE OR REPLACE TEMP VIEW grdp_bronze_profile AS
SELECT *,
    TRIM(CAST(year AS STRING)) AS year_text,
    TRY_CAST(year AS INT) AS year_num,
    TRIM(grdp_per_capita_amount) AS amount_text,
    TRY_CAST(REPLACE(TRIM(grdp_per_capita_amount), ',', '') AS DECIMAL(30,15)) AS amount_num,
    NULLIF(REGEXP_REPLACE(UPPER(TRIM(region_id)), '[^A-Z0-9]', ''), '') AS code_key,
    NULLIF(REGEXP_REPLACE(UPPER(TRIM(region)), '[^A-Z0-9]', ''), '') AS name_key,
    LOWER(TRIM(price_basis)) AS basis_key,
    LOWER(TRIM(geographic_level)) AS level_key
FROM pondolens.dev_bronze.grdp_per_capita;

-- 2. Full coverage and malformed year labels (not hidden by a scope filter).
SELECT COUNT(*) AS total_rows,
    MIN(year_num) AS first_year, MAX(year_num) AS last_year,
    COUNT_IF(year_text IS NULL OR NOT (year_text RLIKE '^[0-9]{4}$')) AS invalid_year_labels,
    COUNT_IF(year_num BETWEEN 2021 AND 2025) AS project_scope_rows
FROM grdp_bronze_profile;

SELECT year, price_basis, unit, geographic_level, COUNT(*) AS row_count
FROM grdp_bronze_profile
GROUP BY year, price_basis, unit, geographic_level
ORDER BY year, price_basis, geographic_level;

SELECT source_name, source_page, source_table, unit, COUNT(*) AS row_count
FROM grdp_bronze_profile
GROUP BY source_name, source_page, source_table, unit
ORDER BY source_name, source_table;

-- 3. Missingness and numeric quality in the project scope.
SELECT COUNT(*) AS total_rows,
    COUNT_IF(code_key IS NULL) AS missing_source_codes,
    COUNT_IF(name_key IS NULL) AS missing_source_names,
    COUNT_IF(amount_text IS NULL OR amount_text = '') AS missing_amounts,
    COUNT_IF(amount_text IS NOT NULL AND amount_text <> '' AND amount_num IS NULL) AS invalid_amounts,
    COUNT_IF(amount_num <= 0) AS nonpositive_amounts,
    COUNT_IF(amount_num <> FLOOR(amount_num)) AS fractional_amounts,
    COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
    MIN(amount_num) AS minimum_amount, MAX(amount_num) AS maximum_amount
FROM grdp_bronze_profile
WHERE year_num BETWEEN 2021 AND 2025;

SELECT * FROM grdp_bronze_profile
WHERE year_num BETWEEN 2021 AND 2025
  AND (name_key IS NULL OR amount_num IS NULL OR amount_num <= 0
       OR basis_key IS NULL OR basis_key NOT IN ('at current prices', 'at constant 2018 prices')
       OR level_key IS NULL OR level_key NOT IN ('region', 'country')
       OR unit IS NULL OR LOWER(TRIM(unit)) <> 'philippine pesos per person');

-- 4. Exact business-data duplicates; ingestion metadata is intentionally excluded.
SELECT source_name, source_page, region_id, region, year,
    grdp_per_capita_amount, price_basis, unit, geographic_level, source_table, source_file,
    COUNT(*) AS row_count
FROM grdp_bronze_profile
GROUP BY source_name, source_page, region_id, region, year,
    grdp_per_capita_amount, price_basis, unit, geographic_level, source_table, source_file
HAVING COUNT(*) > 1;

-- Candidate source keys; final Silver key needs successful canonical mapping.
SELECT year_num, code_key, name_key, basis_key, level_key, COUNT(*) AS row_count
FROM grdp_bronze_profile
WHERE year_num BETWEEN 2021 AND 2025
GROUP BY year_num, code_key, name_key, basis_key, level_key
HAVING COUNT(*) > 1;

-- 5. Geography and source gaps.
SELECT region_id, region, geographic_level,
    MIN(year_num) AS first_year, MAX(year_num) AS last_year, COUNT(*) AS row_count
FROM grdp_bronze_profile
WHERE year_num BETWEEN 2021 AND 2025
GROUP BY region_id, region, geographic_level
ORDER BY geographic_level, region_id;

SELECT source_name, source_page, source_table, region_id, region,
    year, price_basis, grdp_per_capita_amount, unit
FROM grdp_bronze_profile
WHERE code_key = 'NIR'
ORDER BY year_num, price_basis;

-- Canonical identity preview only: validity periods are checked separately below.
-- This view does not authorize historical boundary harmonization.
CREATE OR REPLACE TEMP VIEW grdp_profile_canonical AS
SELECT DISTINCT UPPER(TRIM(region_code)) AS region_code,
    TRIM(region_name) AS region_name,
    CASE WHEN UPPER(TRIM(region_code)) = 'PHL' THEN 'national' ELSE 'region' END AS geographic_level
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL
  AND UPPER(TRIM(region_code)) NOT IN ('CO', 'NW')
  AND (UPPER(TRIM(region_code)) = 'PHL' OR LOWER(TRIM(geographic_level)) = 'region');

SELECT region_code, COUNT(*) AS canonical_variants
FROM grdp_profile_canonical GROUP BY region_code HAVING COUNT(*) > 1;

CREATE OR REPLACE TEMP VIEW grdp_profile_aliases AS
WITH labels AS (
    SELECT UPPER(TRIM(region_code)) AS region_code, source_region AS label
    FROM pondolens.dev_silver.shared_region_crosswalk
    UNION ALL
    SELECT region_code, region_name FROM grdp_profile_canonical
    UNION ALL
    SELECT region_code, region_code FROM grdp_profile_canonical
)
SELECT DISTINCT l.region_code,
    REGEXP_REPLACE(UPPER(TRIM(l.label)), '[^A-Z0-9]', '') AS alias_key
FROM labels l
WHERE NULLIF(TRIM(l.label), '') IS NOT NULL
  AND l.region_code IN (SELECT region_code FROM grdp_profile_canonical);

SELECT alias_key, COUNT(DISTINCT region_code) AS mapped_codes
FROM grdp_profile_aliases
GROUP BY alias_key HAVING COUNT(DISTINCT region_code) > 1;

-- Collect candidates without multiplying the source observations.
CREATE OR REPLACE TEMP VIEW grdp_profile_mapping AS
WITH candidates AS (
    SELECT code_key, name_key, COLLECT_SET(a.region_code) AS candidate_codes
    FROM (SELECT DISTINCT code_key, name_key FROM grdp_bronze_profile
          WHERE year_num BETWEEN 2021 AND 2025) p
    LEFT JOIN grdp_profile_aliases a
      ON p.code_key = a.alias_key OR p.name_key = a.alias_key
    GROUP BY code_key, name_key
)
SELECT p.*, c.candidate_codes,
    SIZE(c.candidate_codes) AS mapping_count,
    CASE WHEN SIZE(c.candidate_codes) = 1 THEN ELEMENT_AT(c.candidate_codes, 1) END AS mapped_region_code
FROM grdp_bronze_profile p
LEFT JOIN candidates c
  ON p.code_key <=> c.code_key AND p.name_key <=> c.name_key
WHERE p.year_num BETWEEN 2021 AND 2025;

SELECT COUNT(*) AS observations,
    COUNT_IF(mapping_count = 0) AS unmapped_observations,
    COUNT_IF(mapping_count > 1) AS conflicting_observations,
    COUNT_IF(mapping_count = 1) AS uniquely_mapped_observations
FROM grdp_profile_mapping;

SELECT region_id, region, candidate_codes, mapping_count, COUNT(*) AS observations
FROM grdp_profile_mapping
GROUP BY region_id, region, candidate_codes, mapping_count
ORDER BY region;

-- 6. Separate canonical identity from temporal applicability.
SELECT DISTINCT p.region_id, p.region, p.mapped_region_code, p.year_num,
    CASE WHEN EXISTS (
        SELECT 1 FROM pondolens.dev_silver.shared_region_crosswalk c
        WHERE UPPER(TRIM(c.region_code)) = p.mapped_region_code
          AND p.year_num BETWEEN COALESCE(c.valid_from_year, 1900)
                             AND COALESCE(c.valid_to_year, 9999)
    ) THEN 'CODE_HAS_ACTIVE_PERIOD' ELSE 'REVIEW_PERIOD' END AS period_status
FROM grdp_profile_mapping p
WHERE p.mapping_count = 1
ORDER BY mapped_region_code, year_num;

SELECT source_region, region_code, region_name, valid_from_year, valid_to_year
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE valid_from_year > valid_to_year;

-- Natural keys after canonical mapping. No output is expected when unique.
SELECT year_num, mapped_region_code, basis_key, level_key, COUNT(*) AS row_count
FROM grdp_profile_mapping
WHERE mapping_count = 1
GROUP BY year_num, mapped_region_code, basis_key, level_key
HAVING COUNT(*) > 1;

-- 7. Country/region and price-basis consistency.
SELECT year_num, COUNT_IF(level_key = 'region' AND basis_key = 'at current prices') AS regional_current,
    COUNT_IF(level_key = 'region' AND basis_key = 'at constant 2018 prices') AS regional_constant,
    COUNT_IF(level_key = 'country' AND basis_key = 'at current prices') AS national_current,
    COUNT_IF(level_key = 'country' AND basis_key = 'at constant 2018 prices') AS national_constant
FROM grdp_bronze_profile
WHERE year_num BETWEEN 2021 AND 2025
GROUP BY year_num ORDER BY year_num;

-- 8. Lineage completeness. File-based ingestion may legitimately have a NULL sheet.
SELECT _source_file, _run_id, COUNT(*) AS row_count,
    COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
          OR NULLIF(TRIM(_source_file), '') IS NULL
          OR NULLIF(TRIM(_landing_file), '') IS NULL
          OR NULLIF(TRIM(_content_hash), '') IS NULL
          OR NULLIF(TRIM(_dataset_hash), '') IS NULL
          OR NULLIF(TRIM(_run_id), '') IS NULL OR _ingested_at IS NULL) AS incomplete_lineage_rows,
    MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM grdp_bronze_profile
GROUP BY _source_file, _run_id;
