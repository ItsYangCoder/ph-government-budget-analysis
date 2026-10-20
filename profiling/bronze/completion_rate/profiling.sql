-- Dataset: completion_rate
-- Table: pondolens.dev_bronze.completion_rate
-- Owner: Rhea Alum
-- Scope: active
-- Execute the complete file in one Databricks SQL session.
-- Persistent tables are read-only; session TEMP VIEWs are allowed.
-- Evidence and unresolved checks: findings.md. Column definitions: data_dictionary.md.

-- 1. Row count, dimension completeness, and rescued records.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT geolocation) AS locations,
    COUNT(DISTINCT level_of_education) AS education_levels,
    COUNT(DISTINCT sex) AS sex_categories,
    COUNT_IF(
        NULLIF(TRIM(indicator), '') IS NULL
        OR NULLIF(TRIM(geolocation), '') IS NULL
        OR NULLIF(TRIM(level_of_education), '') IS NULL
        OR NULLIF(TRIM(sex), '') IS NULL
    ) AS incomplete_dimension_rows,
    COUNT_IF(_rescued_data IS NOT NULL) AS rescued_rows
FROM pondolens.dev_bronze.completion_rate;

-- 2. Duplicate source keys. Expected: no rows.
SELECT
    indicator,
    geolocation,
    level_of_education,
    sex,
    COUNT(*) AS occurrences
FROM pondolens.dev_bronze.completion_rate
GROUP BY indicator, geolocation, level_of_education, sex
HAVING COUNT(*) > 1;

-- 3. Inspect dimension values and their coverage.
SELECT
    geolocation,
    level_of_education,
    sex,
    COUNT(*) AS row_count
FROM pondolens.dev_bronze.completion_rate
GROUP BY geolocation, level_of_education, sex
ORDER BY geolocation, level_of_education, sex;

-- 4. Reshape project years for profiling.
-- Keep raw values so missing markers remain distinguishable.
CREATE OR REPLACE TEMP VIEW completion_rate_profile AS
SELECT
    indicator,
    geolocation,
    level_of_education,
    sex,
    year,
    TRIM(raw_value) AS raw_value,
    TRY_CAST(TRIM(raw_value) AS DECIMAL(10, 3)) AS rate_value
FROM pondolens.dev_bronze.completion_rate
LATERAL VIEW STACK(
    5,
    2021, c_2021,
    2022, c_2022,
    2023, c_2023,
    2024, c_2024,
    2025, c_2025
) years AS year, raw_value;


-- 5. Completeness, parseability, and percentage range per year.
SELECT
    year,
    COUNT(*) AS total_observations,
    COUNT(rate_value) AS numeric_values,
    COUNT_IF(
        raw_value IS NULL OR raw_value = ''
    ) AS null_or_blank,
    COUNT_IF(raw_value = '..') AS two_dot_markers,
    COUNT_IF(raw_value = '...') AS three_dot_markers,
    COUNT_IF(
        raw_value IS NOT NULL
        AND raw_value NOT IN ('', '..', '...')
        AND rate_value IS NULL
    ) AS unexpected_nonnumeric_values,
    COUNT_IF(
        rate_value < 0 OR rate_value > 100
    ) AS outside_percentage_range,
    MIN(rate_value) AS minimum_rate,
    MAX(rate_value) AS maximum_rate
FROM completion_rate_profile
GROUP BY year
ORDER BY year;

-- 6. Identify missing or invalid observations.
SELECT
    year,
    geolocation,
    level_of_education,
    sex,
    raw_value
FROM completion_rate_profile
WHERE rate_value IS NULL
   OR rate_value < 0
   OR rate_value > 100
ORDER BY year, geolocation, level_of_education, sex;



-- 7. Check source lineage completeness.
-- A null _source_sheet is expected for a CSV.
SELECT
    _source_file,
    _run_id,
    COUNT(*) AS row_count,
    COUNT_IF(
        NULLIF(TRIM(_drive_file_id), '') IS NULL
        OR NULLIF(TRIM(_landing_file), '') IS NULL
        OR NULLIF(TRIM(_content_hash), '') IS NULL
        OR NULLIF(TRIM(_dataset_hash), '') IS NULL
        OR NULLIF(TRIM(_run_id), '') IS NULL
        OR _ingested_at IS NULL
    ) AS incomplete_lineage_rows,
    MIN(_ingested_at) AS earliest_ingestion,
    MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.completion_rate
GROUP BY _source_file, _run_id;