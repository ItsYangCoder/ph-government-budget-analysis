-- Unemployment Rate — Data Profiling SQL
-- Original SQL cells retained from the uploaded notebook. Run in Databricks; headings are separated from executable code. Some checks are exploratory and may require adjustment after reviewing the documentation notebook.
-- - Profiling done by Anje

-- 1. Dataset understanding

-- Inspect table schema

DESCRIBE TABLE pondolens.dev_bronze.unemployment_rate;

-- Inspect records with other estimate statuses

SELECT *
FROM pondolens.dev_bronze.unemployment_rate
WHERE estimate_status NOT IN ('Preliminary', 'Final')
LIMIT 30;

-- Inspect table metadata

DESCRIBE DETAIL pondolens.dev_bronze.unemployment_rate;

-- Count records by unit

SELECT
    unit,
    COUNT(*) AS record_count
FROM pondolens.dev_bronze.unemployment_rate
GROUP BY unit
ORDER BY unit;

-- Count records by estimate status

SELECT
    estimate_status,
    COUNT(*) AS record_count
FROM pondolens.dev_bronze.unemployment_rate
GROUP BY estimate_status
ORDER BY record_count DESC;

-- Dataset size and coverage

-- determine overall size and coverage
SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT year) AS total_years,
    COUNT(DISTINCT region) AS total_geographies,
    MIN(year) AS earliest_year,
    MAX(year) AS latest_year
FROM pondolens.dev_bronze.unemployment_rate;

-- Records by year

-- records by year
SELECT
    year,
    COUNT(*) AS total_records,
    COUNT(DISTINCT region) AS distinct_geographies
FROM pondolens.dev_bronze.unemployment_rate
GROUP BY year
ORDER BY year;

-- Geographic records by year

-- list all geographic records per year
SELECT
    year,
    region,
    COUNT(*) AS record_count
FROM pondolens.dev_bronze.unemployment_rate
GROUP BY year, region
ORDER BY year, region;

-- Geographic changes across years

WITH cleaned_data AS (
    SELECT DISTINCT
        CASE
            WHEN TRIM(year) RLIKE '^[0-9]{4}(\\.0+)?$'
            THEN TRY_CAST(
                TRY_CAST(TRIM(year) AS DECIMAL(10,3))
                AS INT
            )
        END AS year,

        UPPER(TRIM(region)) AS region

    FROM pondolens.dev_bronze.unemployment_rate
    WHERE region IS NOT NULL
),

years AS (
    SELECT explode(sequence(2022, 2025)) AS year
),

changes AS (
    SELECT
        y.year,
        r.region,

        CASE
            WHEN curr.region IS NOT NULL
             AND prev.region IS NULL
                THEN 'NEW IN CURRENT YEAR'

            WHEN curr.region IS NULL
             AND prev.region IS NOT NULL
                THEN 'MISSING IN CURRENT YEAR'
        END AS change_status

    FROM years y

    CROSS JOIN (
        SELECT DISTINCT region
        FROM cleaned_data
        WHERE region <> ''
          AND year BETWEEN 2021 AND 2025
    ) r

    LEFT JOIN cleaned_data curr
        ON curr.year = y.year
       AND curr.region = r.region

    LEFT JOIN cleaned_data prev
        ON prev.year = y.year - 1
       AND prev.region = r.region
)

SELECT *
FROM changes
WHERE change_status IS NOT NULL
ORDER BY year, change_status, region;

-- 2. Completeness profiling

-- Missing values summary

SELECT
    COUNT(*) AS total_records,

    SUM(CASE
        WHEN year IS NULL THEN 1 ELSE 0
    END) AS null_years,

    SUM(CASE
        WHEN region IS NULL
          OR TRIM(region) = ''
        THEN 1 ELSE 0
    END) AS missing_regions,

    SUM(CASE
        WHEN value IS NULL
        THEN 1 ELSE 0
    END) AS null_measurements,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN value IS NULL
                THEN 1 ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS measurement_null_percentage

FROM pondolens.dev_bronze.unemployment_rate;

-- Inspect missing values

SELECT *
FROM pondolens.dev_bronze.unemployment_rate
WHERE year IS NULL
   OR region IS NULL
   OR TRIM(region) = ''
   OR value IS NULL
ORDER BY year, region;

-- Region-year coverage

SELECT
    region,

    SUM(CASE WHEN year = 2021.0 THEN 1 ELSE 0 END) AS y2021,
    SUM(CASE WHEN year = 2022.0 THEN 1 ELSE 0 END) AS y2022,
    SUM(CASE WHEN year = 2023.0 THEN 1 ELSE 0 END) AS y2023,
    SUM(CASE WHEN year = 2024.0 THEN 1 ELSE 0 END) AS y2024,
    SUM(CASE WHEN year = 2025.0 THEN 1 ELSE 0 END) AS y2025

FROM pondolens.dev_bronze.unemployment_rate

GROUP BY region
ORDER BY region;

-- 3. Uniqueness and duplicates

-- Candidate duplicates

SELECT
    year,
    region,
    value,
    unit,
    indicator,
    geographic_level,
    estimate_status,
    COUNT(*) AS duplicate_count

FROM pondolens.dev_bronze.unemployment_rate

GROUP BY
    year,
    region,
    value,
    unit,
    indicator,
    geographic_level,
    estimate_status

HAVING COUNT(*) > 1

ORDER BY duplicate_count DESC;

-- Repeated business keys

-- year + region + unit + estimate_status + geographic_level
SELECT
    year,
    region,
    unit,
    estimate_status,
    geographic_level,

    COUNT(*) AS record_count,

    COUNT(DISTINCT
        TRY_CAST(value AS DOUBLE)
    ) AS distinct_values,

    COUNT_IF(value IS NULL)
        AS null_count,

    MIN(TRY_CAST(value AS DOUBLE))
        AS minimum_value,

    MAX(TRY_CAST(value AS DOUBLE))
        AS maximum_value

FROM pondolens.dev_bronze.unemployment_rate

GROUP BY
    year,
    region,
    unit,
    estimate_status,
    geographic_level

HAVING COUNT(*) > 1

ORDER BY record_count DESC;

-- Regional business-key check

-- separate check for regional level only
-- zero rows: proposed key is unique within regional subset
-- year + region + unit + estimate_status

SELECT
    year,
    region,
    unit,
    estimate_status,
    COUNT(*) AS record_count

FROM pondolens.dev_bronze.unemployment_rate

WHERE LOWER(TRIM(geographic_level)) = 'region'

GROUP BY
    year,
    region,
    unit,
    estimate_status

HAVING COUNT(*) > 1

ORDER BY year, region, unit;

-- 4. Validity checks

-- Invalid numeric measurements

-- identify values that cannot be converted to numbers
SELECT
    year,
    region,
    value

FROM pondolens.dev_bronze.unemployment_rate

WHERE value IS NOT NULL
  AND TRY_CAST(
      CAST(value AS STRING) AS DOUBLE
  ) IS NULL;

-- Unemployment rate range

-- Validity check: Unemployment rate must be between 0 and 100
-- no rows, so all unemployment rate between 0 and 100

SELECT
    year,
    region,
    value,
    unit

FROM pondolens.dev_bronze.unemployment_rate

WHERE LOWER(TRIM(unit)) = 'percent'
  AND (
      TRY_CAST(value AS DOUBLE) < 0
      OR TRY_CAST(value AS DOUBLE) > 100
  );

-- Rate summary statistics

SELECT
    year,

    COUNT(*) AS total_records,

    ROUND(MIN(TRY_CAST(value AS DOUBLE)), 2)
        AS minimum_rate,

    ROUND(MAX(TRY_CAST(value AS DOUBLE)), 2)
        AS maximum_rate,

    ROUND(AVG(TRY_CAST(value AS DOUBLE)), 2)
        AS unweighted_average_rate

FROM pondolens.dev_bronze.unemployment_rate

WHERE LOWER(TRIM(unit)) = 'percent'

GROUP BY year
ORDER BY year;

-- 5. Consistency and geographic standardization

-- Region name normalization

SELECT
    UPPER(
        REGEXP_REPLACE(TRIM(region), '[^A-Za-z0-9]', '')
    ) AS normalized_region,

    COLLECT_SET(region) AS original_region_names,

    COUNT(DISTINCT region) AS name_variations

FROM pondolens.dev_bronze.unemployment_rate

WHERE region IS NOT NULL

GROUP BY
    UPPER(
        REGEXP_REPLACE(TRIM(region), '[^A-Za-z0-9]', '')
    )

HAVING COUNT(DISTINCT region) > 1

ORDER BY name_variations DESC;

-- 6. Accuracy and reconciliation

-- Regional versus national counts

WITH filtered AS (
    SELECT
        year,
        LOWER(TRIM(geographic_level)) AS geographic_level,
        TRY_CAST(value AS DOUBLE) AS unemployed_persons
    FROM pondolens.dev_bronze.unemployment_rate
    WHERE LOWER(TRIM(unit)) = 'thousand persons'
      AND LOWER(TRIM(estimate_status)) = 'final'
),

yearly AS (
    SELECT
        year,

        SUM(CASE
            WHEN geographic_level = 'region'
            THEN unemployed_persons
            ELSE 0
        END) AS regional_total,

        MAX(CASE
            WHEN geographic_level = 'country'
            THEN unemployed_persons
        END) AS national_total

    FROM filtered
    GROUP BY year
)

SELECT
    year,
    regional_total,
    national_total,

    regional_total - national_total AS difference,

    ROUND(
        100.0 * (regional_total - national_total)
        / NULLIF(national_total, 0),
        2
    ) AS difference_percentage

FROM yearly
ORDER BY year;
