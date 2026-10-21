{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- ============================================================
-- PondoLens | Gold: fact_regional_indicator
-- Author: Christine Joy D. Balansay
-- Date: 2026-10-20
--
-- Grain: location × year × indicator definition
-- Scope: regional observations, 2021–2025
-- Fact IDs: start at 50001; preserve IDs on reruns
-- Missing education observations: retain NULL and source status
-- ============================================================

SET TIME ZONE 'UTC'
-- pondolens:statement --
-- ============================================================
-- 1. VALIDATE DIMENSION KEYS
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT location_id)
    AND COUNT_IF(
        location_id IS NULL
        OR location_code IS NULL
        OR TRIM(location_code) = ''
        OR geographic_level IS NULL
    ) = 0,
    'STOP: Invalid location dimension keys or attributes.'
)
FROM {{ ref('dim_location') }}
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate regional location codes.'
)
FROM (
    SELECT UPPER(TRIM(location_code))
    FROM {{ ref('dim_location') }}
    WHERE LOWER(TRIM(geographic_level)) = 'region'
    GROUP BY UPPER(TRIM(location_code))
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT year_id)
    AND COUNT(*) = COUNT(DISTINCT year)
    AND COUNT_IF(year_id IS NULL OR year IS NULL) = 0,
    'STOP: Invalid or duplicate year dimension keys.'
)
FROM {{ ref('dim_year') }}
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT indicator_id)
    AND COUNT(*) = COUNT(DISTINCT measure_type)
    AND COUNT_IF(
        indicator_id IS NULL
        OR measure_type IS NULL
        OR unit IS NULL
    ) = 0,
    'STOP: Invalid or duplicate indicator dimension keys.'
)
FROM {{ ref('dim_indicator') }}
-- pondolens:statement --
-- ============================================================
-- 2. PREPARE POVERTY THRESHOLDS
-- Repeated families/population thresholds must agree.
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Missing or conflicting poverty thresholds per region/year.'
)
FROM (
    SELECT
        year,
        UPPER(TRIM(region_code)) AS region_code
    FROM {{ ref('poverty_incidence') }}
    WHERE year BETWEEN 2021 AND 2025
    GROUP BY year, UPPER(TRIM(region_code))
    HAVING COUNT(poverty_threshold_php) <> COUNT(*)
        OR COUNT(DISTINCT poverty_threshold_php) <> 1
) invalid_thresholds
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW fri_poverty_threshold AS
SELECT
    year,
    UPPER(TRIM(region_code)) AS region_code,
    MAX(poverty_threshold_php) AS measurement
FROM {{ ref('poverty_incidence') }}
WHERE year BETWEEN 2021 AND 2025
GROUP BY year, UPPER(TRIM(region_code))
-- pondolens:statement --
-- ============================================================
-- 3. NORMALIZE ALL SOURCE OBSERVATIONS
--
-- GRDP mapping:
--   price_basis = 2018 → constant 2018 prices
--   price_basis = year → current prices
--
-- Unexpected definitions remain NULL and fail validation.
-- ============================================================

CREATE OR REPLACE TEMP VIEW fri_source AS

-- Unemployment
SELECT
    year,
    UPPER(TRIM(region_code)) AS region_code,
    'unemployment_rate' AS measure_type,
    CAST(unemployment_rate AS DECIMAL(28, 10)) AS measurement,
    '% of labor force' AS unit,
    'available' AS value_status,
    '{{ ref('unemployment_rate') }}' AS source_table
FROM {{ ref('unemployment_rate') }}
WHERE year BETWEEN 2021 AND 2025

UNION ALL

-- GRDP per capita
SELECT
    year,
    UPPER(TRIM(region_code)) AS region_code,
    CASE
        WHEN price_basis = 2018
            THEN 'grdp_per_capita_constant_2018_prices'
        WHEN price_basis = year
            THEN 'grdp_per_capita_current_prices'
    END AS measure_type,
    CAST(grdp_per_capita AS DECIMAL(28, 10)) AS measurement,
    CASE
        WHEN price_basis = 2018
            THEN 'PHP/person (2018 prices)'
        WHEN price_basis = year
            THEN 'PHP/person'
    END AS unit,
    'available' AS value_status,
    '{{ ref('grdp_per_capita') }}' AS source_table
FROM {{ ref('grdp_per_capita') }}
WHERE year BETWEEN 2021 AND 2025
  AND LOWER(TRIM(geographic_level)) = 'region'

UNION ALL

-- Government hospitals
SELECT
    year,
    UPPER(TRIM(region_code)) AS region_code,
    CASE
        WHEN LOWER(TRIM(hospital_type)) = 'government'
            THEN 'government_hospital_count'
    END AS measure_type,
    CAST(regulated_hospital_count AS DECIMAL(28, 10)) AS measurement,
    TRIM(unit) AS unit,
    'available' AS value_status,
    '{{ ref('hospital') }}' AS source_table
FROM {{ ref('hospital') }}
WHERE year BETWEEN 2021 AND 2025

UNION ALL

-- Poverty incidence: families and population
SELECT
    year,
    UPPER(TRIM(region_code)) AS region_code,
    CASE
        WHEN TRIM(indicator) IN (
            'poverty_incidence_families',
            'poverty_incidence_population'
        )
            THEN TRIM(indicator)
    END AS measure_type,
    CAST(poverty_incidence_pct AS DECIMAL(28, 10)) AS measurement,
    TRIM(unit) AS unit,
    LOWER(TRIM(value_status)) AS value_status,
    '{{ ref('poverty_incidence') }}' AS source_table
FROM {{ ref('poverty_incidence') }}
WHERE year BETWEEN 2021 AND 2025

UNION ALL

-- One poverty threshold per region/year
SELECT
    year,
    region_code,
    'annual_per_capita_poverty_threshold' AS measure_type,
    CAST(measurement AS DECIMAL(28, 10)) AS measurement,
    'PHP/person/year' AS unit,
    'available' AS value_status,
    '{{ ref('poverty_incidence') }}' AS source_table
FROM fri_poverty_threshold

UNION ALL

-- Education: retain missing source observations and their status
SELECT
    year,
    UPPER(TRIM(region_code)) AS region_code,

    CASE
        WHEN TRIM(indicator) = '4.1.2 Completion rate'
         AND TRIM(unit) = 'percent'
         AND TRIM(level_of_education) IN (
             'Elementary',
             'Secondary (Junior High School)',
             'Secondary (Senior High School)'
         )
         AND TRIM(sex) IN ('Both Sexes', 'Male', 'Female')
        THEN CONCAT(
            CASE TRIM(level_of_education)
                WHEN 'Elementary'
                    THEN 'elementary'
                WHEN 'Secondary (Junior High School)'
                    THEN 'junior_high'
                WHEN 'Secondary (Senior High School)'
                    THEN 'senior_high'
            END,
            '_completion_rate_',
            CASE TRIM(sex)
                WHEN 'Both Sexes' THEN 'both_sexes'
                WHEN 'Male' THEN 'male'
                WHEN 'Female' THEN 'female'
            END
        )
    END AS measure_type,

    CAST(completion_rate AS DECIMAL(28, 10)) AS measurement,
    CASE WHEN TRIM(unit) = 'percent' THEN '%' END AS unit,
    LOWER(TRIM(value_status)) AS value_status,
    '{{ ref('completion_rate') }}' AS source_table

FROM {{ ref('completion_rate') }}
WHERE year BETWEEN 2021 AND 2025
  AND LOWER(TRIM(geographic_level)) = 'region'

UNION ALL

-- Service access
SELECT
    year,
    UPPER(TRIM(region_code)) AS region_code,
    TRIM(service_measure) AS measure_type,
    CAST(value AS DECIMAL(28, 10)) AS measurement,
    TRIM(unit) AS unit,
    'available' AS value_status,
    '{{ ref('service_access') }}' AS source_table
FROM {{ ref('service_access') }}
WHERE year IN (2022, 2024)
-- pondolens:statement --
-- ============================================================
-- 4. DEFINE REGIONAL SCOPE
--
-- Explicitly exclude national/office codes.
-- Unknown codes are retained so missing mappings fail later.
-- ============================================================

CREATE OR REPLACE TEMP VIEW fri_regional_source AS
SELECT *
FROM fri_source
WHERE region_code IS NULL
   OR region_code NOT IN (
       'NW',
       'PHL',
       'CO',
       'NATIONAL',
       'NATIONWIDE',
       'PHILIPPINES',
       'CENTRAL OFFICE'
   )
-- pondolens:statement --
-- Review exclusions before loading.
SELECT
    source_table,
    region_code,
    COUNT(*) AS excluded_rows
FROM fri_source
WHERE region_code IN (
    'NW',
    'PHL',
    'CO',
    'NATIONAL',
    'NATIONWIDE',
    'PHILIPPINES',
    'CENTRAL OFFICE'
)
GROUP BY source_table, region_code
ORDER BY source_table, region_code
-- pondolens:statement --
-- ============================================================
-- 5. VALIDATE SOURCE DEFINITIONS, STATUS, AND VALUES
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(DISTINCT measure_type) = 19
    AND COUNT_IF(
        region_code IS NULL OR region_code = ''
        OR measure_type IS NULL OR measure_type = ''
        OR unit IS NULL OR unit = ''
        OR value_status IS NULL
        OR value_status NOT IN (
            'available',
            'source_marker_three_dots',
            'source_marker_two_dots'
        )

        -- Available observations must have measurements.
        OR (
            value_status = 'available'
            AND measurement IS NULL
        )

        -- Missing source markers are allowed only for education.
        OR (
            value_status <> 'available'
            AND (
                source_table <> '{{ ref('completion_rate') }}'
                OR measurement IS NOT NULL
            )
        )

        -- All included measures must be nonnegative.
        OR measurement < 0

        -- Percentage measures must use the expected scale.
        OR (
            unit IN (
                '%',
                '% of labor force',
                '% of families',
                '% of population',
                '% of consenting families'
            )
            AND measurement > 100
        )

        -- Hospital counts must be whole numbers.
        OR (
            measure_type = 'government_hospital_count'
            AND measurement <> FLOOR(measurement)
        )

        -- Monetary measures must be positive.
        OR (
            measure_type IN (
                'grdp_per_capita_current_prices',
                'grdp_per_capita_constant_2018_prices',
                'annual_per_capita_poverty_threshold'
            )
            AND measurement <= 0
        )
    ) = 0,
    'STOP: Invalid definition, source status, measurement, or scale.'
)
FROM fri_regional_source
-- pondolens:statement --
-- No arbitrary deduplication or averaging.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate source region/year/measure observations.'
)
FROM (
    SELECT
        region_code,
        year,
        measure_type
    FROM fri_regional_source
    GROUP BY region_code, year, measure_type
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- Validate the known service-access scope.
SELECT ASSERT_TRUE(
    COUNT(*) = 102,
    'STOP: Expected 102 regional service-access observations.'
)
FROM fri_regional_source
WHERE source_table = '{{ ref('service_access') }}'
-- pondolens:statement --
-- ============================================================
-- 6. RESOLVE DIMENSION FOREIGN KEYS
-- LEFT JOIN prevents unmatched observations from disappearing.
-- ============================================================

CREATE OR REPLACE TEMP VIEW fri_mapped AS
SELECT
    l.location_id,
    y.year_id,
    d.indicator_id,
    s.measurement,
    s.value_status,
    s.source_table,

    -- Diagnostic attributes; not persisted in the fact.
    s.region_code,
    s.year,
    s.measure_type,
    s.unit

FROM fri_regional_source s

LEFT JOIN {{ ref('dim_location') }} l
    ON s.region_code = UPPER(TRIM(l.location_code))
   AND LOWER(TRIM(l.geographic_level)) = 'region'

LEFT JOIN {{ ref('dim_year') }} y
    ON s.year = y.year

LEFT JOIN {{ ref('dim_indicator') }} d
    ON s.measure_type = d.measure_type
   AND s.unit = d.unit
-- pondolens:statement --
-- Diagnostic: expected NO ROWS.
SELECT
    source_table,
    region_code,
    year,
    measure_type,
    unit,
    location_id,
    year_id,
    indicator_id
FROM fri_mapped
WHERE location_id IS NULL
   OR year_id IS NULL
   OR indicator_id IS NULL
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT_IF(
        location_id IS NULL
        OR year_id IS NULL
        OR indicator_id IS NULL
    ) = 0,
    'STOP: Missing location, year, or indicator dimension match.'
)
FROM fri_mapped
-- pondolens:statement --
SELECT ASSERT_TRUE(
    (SELECT COUNT(*) FROM fri_mapped)
        = (SELECT COUNT(*) FROM fri_regional_source),
    'STOP: Dimension joins changed the source row count.'
)
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate mapped location/year/indicator keys.'
)
FROM (
    SELECT
        location_id,
        year_id,
        indicator_id
    FROM fri_mapped
    GROUP BY location_id, year_id, indicator_id
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 7. CREATE THE PERSISTENT FACT TABLE
-- Measurement is nullable to preserve missing education values.
-- ============================================================

CREATE TABLE IF NOT EXISTS
{{ this }} (
    fact_indicator_id BIGINT NOT NULL,
    location_id BIGINT NOT NULL,
    year_id INT NOT NULL,
    indicator_id INT NOT NULL,
    measurement DECIMAL(28, 10),
    value_status STRING NOT NULL,
    source_table STRING NOT NULL,
    processed_at TIMESTAMP NOT NULL
)
USING DELTA
COMMENT 'Regional development observations by location, year, and indicator'
-- pondolens:statement --
-- ============================================================
-- 8. VALIDATE EXISTING TARGET
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT fact_indicator_id)
    AND COUNT_IF(
        fact_indicator_id IS NULL
        OR fact_indicator_id < 50001
        OR location_id IS NULL
        OR year_id IS NULL
        OR indicator_id IS NULL
        OR processed_at IS NULL
    ) = 0,
    'STOP: Existing fact has invalid or duplicate identifiers.'
)
FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing fact contains duplicate business keys.'
)
FROM (
    SELECT
        location_id,
        year_id,
        indicator_id
    FROM {{ this }}
    GROUP BY location_id, year_id, indicator_id
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 9. ASSIGN IDs ONLY TO NEW BUSINESS KEYS
-- Single writer required.
-- ============================================================

CREATE OR REPLACE TEMP VIEW fri_new_ids AS
SELECT
    s.location_id,
    s.year_id,
    s.indicator_id,

    m.max_id + ROW_NUMBER() OVER (
        ORDER BY s.location_id, s.year_id, s.indicator_id
    ) AS fact_indicator_id

FROM (
    SELECT s.*
    FROM fri_mapped s
    LEFT ANTI JOIN {{ this }} t
        ON s.location_id = t.location_id
       AND s.year_id = t.year_id
       AND s.indicator_id = t.indicator_id
) s

CROSS JOIN (
    SELECT COALESCE(
        MAX(fact_indicator_id),
        CAST(50000 AS BIGINT)
    ) AS max_id
    FROM {{ this }}
) m
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW fri_upsert AS
SELECT
    COALESCE(
        t.fact_indicator_id,
        n.fact_indicator_id
    ) AS fact_indicator_id,

    s.location_id,
    s.year_id,
    s.indicator_id,
    s.measurement,
    s.value_status,
    s.source_table

FROM fri_mapped s

LEFT JOIN {{ this }} t
    ON s.location_id = t.location_id
   AND s.year_id = t.year_id
   AND s.indicator_id = t.indicator_id

LEFT JOIN fri_new_ids n
    ON s.location_id = n.location_id
   AND s.year_id = n.year_id
   AND s.indicator_id = n.indicator_id
-- pondolens:statement --
-- ============================================================
-- 10. MERGE INTO THE FACT TABLE
-- Preserve unchanged IDs and processed_at.
-- ============================================================

MERGE INTO {{ this }} t
USING fri_upsert s
ON  t.location_id = s.location_id
AND t.year_id = s.year_id
AND t.indicator_id = s.indicator_id

WHEN MATCHED AND (
       NOT (t.measurement <=> s.measurement)
    OR NOT (t.value_status <=> s.value_status)
    OR NOT (t.source_table <=> s.source_table)
)
THEN UPDATE SET
    t.measurement = s.measurement,
    t.value_status = s.value_status,
    t.source_table = s.source_table,
    t.processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN INSERT (
    fact_indicator_id,
    location_id,
    year_id,
    indicator_id,
    measurement,
    value_status,
    source_table,
    processed_at
)
VALUES (
    s.fact_indicator_id,
    s.location_id,
    s.year_id,
    s.indicator_id,
    s.measurement,
    s.value_status,
    s.source_table,
    CURRENT_TIMESTAMP()
)
-- pondolens:statement --
-- ============================================================
-- 11. VALIDATE PERSISTED OUTPUT
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT fact_indicator_id),
    'STOP: Duplicate fact IDs after loading.'
)
FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate fact business keys after loading.'
)
FROM (
    SELECT location_id, year_id, indicator_id
    FROM {{ this }}
    GROUP BY location_id, year_id, indicator_id
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = (SELECT COUNT(*) FROM fri_mapped)
    AND COUNT_IF(
        t.fact_indicator_id IS NULL
        OR NOT (t.measurement <=> s.measurement)
        OR NOT (t.value_status <=> s.value_status)
        OR NOT (t.source_table <=> s.source_table)
        OR t.processed_at IS NULL
    ) = 0,
    'STOP: Persisted fact does not match validated source observations.'
)
FROM fri_mapped s
LEFT JOIN {{ this }} t
    ON s.location_id = t.location_id
   AND s.year_id = t.year_id
   AND s.indicator_id = t.indicator_id
-- pondolens:statement --
-- Check foreign keys across the entire saved fact.
SELECT ASSERT_TRUE(
    COUNT_IF(
        l.location_id IS NULL
        OR LOWER(TRIM(l.geographic_level)) <> 'region'
        OR y.year_id IS NULL
        OR d.indicator_id IS NULL
    ) = 0,
    'STOP: Saved fact contains invalid dimension references.'
)
FROM {{ this }} f
LEFT JOIN {{ ref('dim_location') }} l
    ON f.location_id = l.location_id
LEFT JOIN {{ ref('dim_year') }} y
    ON f.year_id = y.year_id
LEFT JOIN {{ ref('dim_indicator') }} d
    ON f.indicator_id = d.indicator_id
-- pondolens:statement --
-- ============================================================
-- 12. REVIEW COVERAGE AND MISSING OBSERVATIONS
-- ============================================================

SELECT
    y.year,
    d.indicator_id,
    d.measure_type,
    d.unit,
    f.value_status,
    COUNT(*) AS row_count,
    COUNT(DISTINCT f.location_id) AS region_count,
    COUNT(f.measurement) AS populated_measurements,
    MIN(f.measurement) AS min_value,
    MAX(f.measurement) AS max_value
FROM {{ this }} f
JOIN {{ ref('dim_year') }} y
    ON f.year_id = y.year_id
JOIN {{ ref('dim_indicator') }} d
    ON f.indicator_id = d.indicator_id
GROUP BY
    y.year,
    d.indicator_id,
    d.measure_type,
    d.unit,
    f.value_status
ORDER BY y.year, d.indicator_id, f.value_status
-- pondolens:statement --
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT fact_indicator_id) AS unique_fact_ids,
    COUNT(DISTINCT indicator_id) AS indicator_count,
    COUNT_IF(measurement IS NULL) AS missing_measurements,
    MIN(fact_indicator_id) AS first_fact_id,
    MAX(fact_indicator_id) AS last_fact_id
FROM {{ this }}
