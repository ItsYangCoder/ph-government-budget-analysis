-- Population: Bronze profiling
-- Assigned to: Razzelle Boreros
-- Documented by: Razzelle Boreros
-- Run in one SQL session. Stored Bronze records are unchanged.

-- 1. Prepare text, numbers and dates for checking.
CREATE OR REPLACE TEMP VIEW population_profile AS
SELECT
    *,
    UPPER(REGEXP_REPLACE(TRIM(region_name), r'\s+', ' ')) AS region_key,
    UPPER(TRIM(age_group)) AS age_key,
    UPPER(TRIM(sex)) AS sex_key,
    TRY_CAST(REPLACE(TRIM(year), ',', '') AS DECIMAL(38, 10)) AS year_num,
    TRY_CAST(REPLACE(TRIM(age_min), ',', '') AS DECIMAL(38, 10)) AS age_min_num,
    TRY_CAST(REPLACE(TRIM(age_max), ',', '') AS DECIMAL(38, 10)) AS age_max_num,
    TRY_CAST(REPLACE(TRIM(population), ',', '') AS DECIMAL(38, 10)) AS population_num,
    TRY_CAST(SUBSTRING(TRIM(reference_date), 1, 10) AS DATE) AS reference_day
FROM pondolens.dev_bronze.population;


-- 2. Count rows and check available years, regions and population groups.
SELECT
    COUNT(*) AS total_rows,
    MIN(year_num) AS earliest_year,
    MAX(year_num) AS latest_year,
    COUNT(DISTINCT region_key) AS total_areas,
    COUNT(DISTINCT CASE
        WHEN region_key NOT IN ('', 'NULL', 'PHILIPPINES')
        THEN region_key
    END) AS regional_labels,
    COUNT(DISTINCT age_key) AS age_groups,
    COUNT(DISTINCT sex_key) AS sex_categories,
    COUNT_IF(
        year_num BETWEEN 2021 AND 2025
        AND sex_key = 'BOTH'
        AND region_key NOT IN ('', 'NULL', 'PHILIPPINES')
    ) AS proposed_silver_rows,
    COUNT_IF(
        year_num BETWEEN 2021 AND 2025
        AND age_key = 'TOTAL'
        AND sex_key = 'BOTH'
        AND region_key NOT IN ('', 'NULL', 'PHILIPPINES')
    ) AS regional_total_both_rows
FROM population_profile;


-- 3. Check column types, source details and ingestion dates.
SELECT
    column_name,
    full_data_type AS current_type
FROM pondolens.information_schema.columns
WHERE table_schema = 'dev_bronze'
  AND table_name = 'population'
ORDER BY ordinal_position;

SELECT
    source,
    _source_file,
    _source_sheet,
    COUNT(*) AS row_count,
    COUNT(DISTINCT _run_id) AS ingestion_runs,
    MIN(_ingested_at) AS earliest_ingestion,
    MAX(_ingested_at) AS latest_ingestion
FROM population_profile
GROUP BY source, _source_file, _source_sheet
ORDER BY source, _source_file, _source_sheet;


-- 4. Check missing values, invalid numbers and numeric ranges.
CREATE OR REPLACE TEMP VIEW population_values AS
SELECT
    field,
    TRIM(raw_value) AS raw_value,
    raw_value IS NULL
        OR LOWER(TRIM(raw_value)) IN ('', 'null') AS is_missing,
    TRY_CAST(REPLACE(TRIM(raw_value), ',', '') AS DECIMAL(38, 10)) AS numeric_value
FROM pondolens.dev_bronze.population
LATERAL VIEW STACK(
    20,
    'region_name', CAST(region_name AS STRING),
    'age_group', CAST(age_group AS STRING),
    'age_min', CAST(age_min AS STRING),
    'age_max', CAST(age_max AS STRING),
    'sex', CAST(sex AS STRING),
    'year', CAST(year AS STRING),
    'reference_date', CAST(reference_date AS STRING),
    'population', CAST(population AS STRING),
    'source', CAST(source AS STRING),
    '_rescued_data', CAST(_rescued_data AS STRING),
    '_drive_file_id', CAST(_drive_file_id AS STRING),
    '_source_file', CAST(_source_file AS STRING),
    '_landing_file', CAST(_landing_file AS STRING),
    '_source_modified_at', CAST(_source_modified_at AS STRING),
    '_source_sheet', CAST(_source_sheet AS STRING),
    '_content_hash', CAST(_content_hash AS STRING),
    '_header_map', CAST(_header_map AS STRING),
    '_dataset_hash', CAST(_dataset_hash AS STRING),
    '_run_id', CAST(_run_id AS STRING),
    '_ingested_at', CAST(_ingested_at AS STRING)
) s AS field, raw_value;

WITH checked AS (
    SELECT
        *,
        field IN ('year', 'age_min', 'age_max', 'population') AS is_numeric,
        numeric_value IS NOT NULL
            AND numeric_value IS NOT NULL AS is_finite
    FROM population_values
)
SELECT
    field,
    COUNT(*) AS total_rows,
    COUNT_IF(is_missing) AS missing_values,
    CASE WHEN is_numeric THEN
        COUNT_IF(raw_value IN ('-', '–', '—'))
    END AS dash_markers,
    CASE WHEN is_numeric THEN
        COUNT_IF(
            NOT is_missing
            AND raw_value NOT IN ('-', '–', '—')
            AND NOT is_finite
        )
    END AS invalid_numeric_values,
    CASE WHEN is_numeric THEN
        COUNT_IF(is_finite AND numeric_value < 0)
    END AS negative_values,
    CASE WHEN is_numeric THEN
        COUNT_IF(is_finite AND numeric_value = 0)
    END AS zero_values,
    CASE WHEN is_numeric THEN
        COUNT_IF(is_finite AND numeric_value <> FLOOR(numeric_value))
    END AS fractional_values,
    MIN(CASE WHEN is_numeric AND is_finite THEN numeric_value END) AS minimum,
    MAX(CASE WHEN is_numeric AND is_finite THEN numeric_value END) AS maximum
FROM checked
GROUP BY field, is_numeric
ORDER BY field;


-- 5. Review region names, age groups, age limits and sex labels.
SELECT
    region_name,
    region_key,
    CASE
        WHEN region_key = 'PHILIPPINES' THEN 'national'
        WHEN region_key IS NULL OR region_key IN ('', 'NULL') THEN 'unknown'
        ELSE 'regional'
    END AS proposed_geographic_level,
    COUNT(*) AS row_count
FROM population_profile
GROUP BY region_name, region_key
ORDER BY region_key, region_name;

SELECT
    age_key AS age_group,
    age_min,
    age_max,
    COUNT(*) AS row_count
FROM population_profile
GROUP BY age_key, age_min, age_max
ORDER BY age_key, age_min, age_max;

SELECT
    sex,
    sex_key,
    COUNT(*) AS row_count
FROM population_profile
GROUP BY sex, sex_key
ORDER BY sex_key, sex;


-- 6. Check valid years, dates, population values and expected missing age limits.
WITH checked AS (
    SELECT
        *,
        age_min IS NULL
            OR LOWER(TRIM(age_min)) IN ('', 'null') AS missing_age_min,
        age_max IS NULL
            OR LOWER(TRIM(age_max)) IN ('', 'null') AS missing_age_max
    FROM population_profile
)
SELECT
    COUNT(*) AS total_rows,
    COUNT_IF(
        year_num IS NULL
                OR year_num NOT BETWEEN 1 AND 9999
        OR year_num <> FLOOR(year_num)
    ) AS invalid_years,
    COUNT_IF(
        population_num IS NULL
                OR population_num < 0
        OR population_num <> FLOOR(population_num)
        OR TRY_CAST(population_num AS BIGINT) IS NULL
    ) AS invalid_population,
    COUNT_IF(reference_day IS NULL) AS invalid_reference_dates,
    COUNT_IF(
        reference_day IS NOT NULL
        AND year_num IS NOT NULL
        AND YEAR(reference_day) <> year_num
    ) AS reference_year_mismatches,
    COUNT_IF(
        reference_day IS NOT NULL
        AND (MONTH(reference_day) <> 7 OR DAY(reference_day) <> 1)
    ) AS reference_dates_not_july_1,
    COUNT_IF(
        sex_key IS NULL OR sex_key NOT IN ('BOTH', 'MALE', 'FEMALE')
    ) AS unexpected_sex,
    COUNT_IF(
        age_key IS NULL OR age_key NOT IN (
            'TOTAL', '0 - 4', '5 - 9', '10 - 14', '15 - 19',
            '20 - 24', '25 - 29', '30 - 34', '35 - 39',
            '40 - 44', '45 - 49', '50 - 54', '55 - 59',
            '60 - 64', '65 - 69', '70 - 74', '75 - 79',
            '80 - 84', '85 AND OVER'
        )
    ) AS unexpected_age_groups,
    COUNT_IF(
        missing_age_min AND age_key = 'TOTAL'
    ) AS expected_missing_age_min,
    COUNT_IF(
        missing_age_max AND age_key IN ('TOTAL', '85 AND OVER')
    ) AS expected_missing_age_max,
    COUNT_IF(
        missing_age_min AND (age_key IS NULL OR age_key <> 'TOTAL')
    ) AS unexpected_missing_age_min,
    COUNT_IF(
        missing_age_max
        AND (age_key IS NULL OR age_key NOT IN ('TOTAL', '85 AND OVER'))
    ) AS unexpected_missing_age_max,
    COUNT_IF(
        _rescued_data IS NOT NULL
        AND LOWER(TRIM(CAST(_rescued_data AS STRING))) NOT IN ('', 'null')
    ) AS rescued_rows
FROM checked;


-- 7. Check duplicate rows and repeated keys.
-- Check all sexes in Bronze, but use BOTH only for the planned Silver records.
WITH records AS (
    SELECT
        'Exact duplicates: all columns' AS check_name,
        TO_JSON(STRUCT(*)) AS record
    FROM pondolens.dev_bronze.population

    UNION ALL

    SELECT
        'Exact duplicates: data columns',
        TO_JSON(STRUCT(
            region_name, year, age_group, sex,
            age_min, age_max, population, reference_date, source
        ))
    FROM pondolens.dev_bronze.population

    UNION ALL

    SELECT
        'Bronze key: region + year + age group + sex',
        TO_JSON(STRUCT(region_key, year_num, age_key, sex_key))
    FROM population_profile

    UNION ALL

    SELECT
        'Silver scope key: region + year + age group',
        TO_JSON(STRUCT(region_key, year_num, age_key))
    FROM population_profile
    WHERE year_num BETWEEN 2021 AND 2025
      AND sex_key = 'BOTH'
      AND region_key NOT IN ('', 'NULL', 'PHILIPPINES')
),
grouped AS (
    SELECT
        check_name,
        record,
        COUNT(*) AS occurrences
    FROM records
    GROUP BY check_name, record
),
labels AS (
    SELECT * FROM VALUES
        ('Exact duplicates: all columns'),
        ('Exact duplicates: data columns'),
        ('Bronze key: region + year + age group + sex'),
        ('Silver scope key: region + year + age group')
    AS t(check_name)
)
SELECT
    l.check_name,
    COALESCE(SUM(g.occurrences), 0) AS total_rows,
    COUNT_IF(g.occurrences > 1) AS duplicate_groups,
    COALESCE(SUM(
        CASE WHEN g.occurrences > 1 THEN g.occurrences - 1 ELSE 0 END
    ), 0) AS excess_rows
FROM labels l
LEFT JOIN grouped g ON l.check_name = g.check_name
GROUP BY l.check_name
ORDER BY l.check_name;


-- 8. Check regional coverage and compare regional sums with Philippines totals for 2021–2025.
-- Use all ages (TOTAL) and both sexes (BOTH) to avoid double counting.
-- Expected regions come from this snapshot, not an independent reference list.
WITH years AS (
    SELECT EXPLODE(SEQUENCE(2021, 2025)) AS year
),
regions AS (
    SELECT DISTINCT region_key
    FROM population_profile
    WHERE region_key NOT IN ('', 'NULL', 'PHILIPPINES')
),
totals AS (
    SELECT
        region_key,
        year_num,
        COUNT(*) AS row_count,
        COUNT_IF(
            population_num IS NOT NULL
                        AND population_num >= 0
            AND population_num = FLOOR(population_num)
            AND TRY_CAST(population_num AS BIGINT) IS NOT NULL
        ) AS valid_population_rows,
        SUM(TRY_CAST(population_num AS BIGINT)) AS population_sum
    FROM population_profile
    WHERE year_num BETWEEN 2021 AND 2025
      AND age_key = 'TOTAL'
      AND sex_key = 'BOTH'
    GROUP BY region_key, year_num
),
regional AS (
    SELECT
        y.year,
        COUNT(*) AS expected_source_regions,
        SUM(COALESCE(t.row_count, 0)) AS regional_total_both_rows,
        COUNT_IF(t.row_count IS NULL) AS missing_regions,
        COUNT_IF(t.row_count > 1) AS repeated_regions,
        COUNT_IF(
            t.row_count = 1 AND t.valid_population_rows = 1
        ) AS valid_regions,
        SUM(t.population_sum) AS regional_population
    FROM years y
    CROSS JOIN regions r
    LEFT JOIN totals t
        ON r.region_key = t.region_key
       AND y.year = t.year_num
    GROUP BY y.year
)
SELECT
    y.year,
    COALESCE(r.expected_source_regions, 0) AS expected_source_regions,
    COALESCE(r.regional_total_both_rows, 0) AS regional_total_both_rows,
    r.missing_regions,
    r.repeated_regions,
    r.valid_regions,
    COALESCE(n.row_count, 0) AS philippines_rows,
    r.regional_population,
    n.population_sum AS philippines_population,
    CASE
        WHEN r.valid_regions = r.expected_source_regions
         AND r.expected_source_regions > 0
         AND n.row_count = 1
         AND n.valid_population_rows = 1
        THEN r.regional_population - n.population_sum
    END AS regional_minus_philippines
FROM years y
LEFT JOIN regional r ON y.year = r.year
LEFT JOIN totals n
    ON y.year = n.year_num
   AND n.region_key = 'PHILIPPINES'
ORDER BY y.year;

-- 9. Check age bounds independently of whether they parse as numbers.
SELECT COUNT_IF(
    (age_key = 'TOTAL' AND (age_min_num IS NOT NULL OR age_max_num IS NOT NULL))
    OR (age_key = '85 AND OVER' AND (age_min_num IS NULL OR age_min_num <> 85
        OR NULLIF(TRIM(age_max), '') IS NOT NULL
           AND LOWER(TRIM(age_max)) <> 'null'))
    OR (age_key NOT IN ('TOTAL', '85 AND OVER') AND (
        age_min_num IS NULL OR age_max_num IS NULL
        OR age_min_num < 0 OR age_max_num < age_min_num
        OR age_min_num <> FLOOR(age_min_num)
        OR age_max_num <> FLOOR(age_max_num)
        OR age_key <> CONCAT(CAST(CAST(age_min_num AS INT) AS STRING),
            ' - ', CAST(CAST(age_max_num AS INT) AS STRING))
    ))
) AS inconsistent_age_bounds
FROM population_profile;

-- 10. Required ingestion lineage. Run before marking this check as passed.
SELECT _source_file, _run_id, COUNT(*) AS row_count,
    COUNT_IF(
        NULLIF(TRIM(_drive_file_id), '') IS NULL
        OR NULLIF(TRIM(_source_file), '') IS NULL
        OR NULLIF(TRIM(_landing_file), '') IS NULL
        OR NULLIF(TRIM(_content_hash), '') IS NULL
        OR NULLIF(TRIM(_dataset_hash), '') IS NULL
        OR NULLIF(TRIM(_run_id), '') IS NULL
        OR _ingested_at IS NULL
    ) AS incomplete_lineage_rows
FROM population_profile
GROUP BY _source_file, _run_id;
