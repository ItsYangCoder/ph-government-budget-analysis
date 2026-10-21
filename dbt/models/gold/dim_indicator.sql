{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- ============================================================
-- PondoLens | Gold: dim_indicator
-- Author: Christine Joy D. Balansay
-- Date: 2026-10-20
--
-- Grain: one row per distinct indicator definition
-- Fixed IDs: 40001–40019
-- Update strategy: Type 1 (overwrite changed descriptive fields)
--
-- Region, year, and measurement belong in the fact table.
-- ============================================================

SET TIME ZONE 'UTC'
-- pondolens:statement --
-- ============================================================
-- 1. DEFINE THE APPROVED INDICATOR REGISTRY
-- IDs must remain stable after fact tables reference them.
-- ============================================================

CREATE OR REPLACE TEMP VIEW dim_indicator_seed AS
SELECT *
FROM VALUES
    (
        40001,
        'unemployment',
        'unemployment_rate',
        '% of labor force'
    ),
    (
        40002,
        'grdp_per_capita',
        'grdp_per_capita_current_prices',
        'PHP/person'
    ),
    (
        40003,
        'grdp_per_capita',
        'grdp_per_capita_constant_2018_prices',
        'PHP/person (2018 prices)'
    ),
    (
        40004,
        'health',
        'government_hospital_count',
        'hospitals'
    ),
    (
        40005,
        'poverty',
        'poverty_incidence_families',
        '% of families'
    ),
    (
        40006,
        'poverty',
        'poverty_incidence_population',
        '% of population'
    ),
    (
        40007,
        'education',
        'elementary_completion_rate_both_sexes',
        '%'
    ),
    (
        40008,
        'education',
        'elementary_completion_rate_male',
        '%'
    ),
    (
        40009,
        'education',
        'elementary_completion_rate_female',
        '%'
    ),
    (
        40010,
        'education',
        'junior_high_completion_rate_both_sexes',
        '%'
    ),
    (
        40011,
        'education',
        'junior_high_completion_rate_male',
        '%'
    ),
    (
        40012,
        'education',
        'junior_high_completion_rate_female',
        '%'
    ),
    (
        40013,
        'education',
        'senior_high_completion_rate_both_sexes',
        '%'
    ),
    (
        40014,
        'education',
        'senior_high_completion_rate_male',
        '%'
    ),
    (
        40015,
        'education',
        'senior_high_completion_rate_female',
        '%'
    ),
    (
        40016,
        'poverty',
        'annual_per_capita_poverty_threshold',
        'PHP/person/year'
    ),
    (
        40017,
        'service_access',
        'at_least_basic_drinking_water_access',
        '% of families'
    ),
    (
        40018,
        'service_access',
        'basic_sanitation_access',
        '% of families'
    ),
    (
        40019,
        'service_access',
        'basic_handwashing_facilities',
        '% of consenting families'
    )
AS seed (
    indicator_id,
    indicator,
    measure_type,
    unit
)
-- pondolens:statement --
-- ============================================================
-- 2. VALIDATE THE REGISTRY
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 19
    AND COUNT(DISTINCT indicator_id) = 19
    AND COUNT(DISTINCT measure_type) = 19
    AND MIN(indicator_id) = 40001
    AND MAX(indicator_id) = 40019
    AND COUNT_IF(
        indicator_id IS NULL
        OR indicator IS NULL OR TRIM(indicator) = ''
        OR measure_type IS NULL OR TRIM(measure_type) = ''
        OR unit IS NULL OR TRIM(unit) = ''
    ) = 0,
    'STOP: Invalid registry count, IDs, definitions, or required fields.'
)
FROM dim_indicator_seed
-- pondolens:statement --
-- ============================================================
-- 3. CHECK SERVICE-ACCESS DEFINITIONS AGAINST SILVER
-- Every distinct Silver measure/unit must have a registry match.
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 3,
    'STOP: Expected three distinct service-access definitions in Silver.'
)
FROM (
    SELECT DISTINCT service_measure, unit
    FROM {{ ref('service_access') }}
) silver_definitions
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Service-access Silver definition is missing or has a different unit.'
)
FROM (
    SELECT DISTINCT service_measure, unit
    FROM {{ ref('service_access') }}
) s
LEFT ANTI JOIN dim_indicator_seed d
    ON d.indicator = 'service_access'
   AND s.service_measure = d.measure_type
   AND s.unit = d.unit
-- pondolens:statement --
-- ============================================================
-- 4. CREATE THE PERSISTENT GOLD TABLE
-- Requires pondolens.dev_gold to exist.
-- ============================================================

CREATE TABLE IF NOT EXISTS {{ this }} (
    indicator_id INT NOT NULL
        COMMENT 'Stable indicator identifier used by fact tables',

    indicator STRING NOT NULL
        COMMENT 'Indicator group or subject',

    measure_type STRING NOT NULL
        COMMENT 'Unique standardized indicator definition',

    unit STRING NOT NULL
        COMMENT 'Measurement unit including denominator or price basis',

    processed_at TIMESTAMP NOT NULL
        COMMENT 'Timestamp of insertion or last descriptive change'
)
USING DELTA
COMMENT 'PondoLens indicator definitions for regional development measurements'
-- pondolens:statement --
-- ============================================================
-- 5. CHECK EXISTING TARGET INTEGRITY
-- Protect reruns from duplicate IDs or definitions.
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT indicator_id)
    AND COUNT(*) = COUNT(DISTINCT measure_type)
    AND COUNT_IF(
        indicator_id IS NULL
        OR indicator IS NULL OR TRIM(indicator) = ''
        OR measure_type IS NULL OR TRIM(measure_type) = ''
        OR unit IS NULL OR TRIM(unit) = ''
        OR processed_at IS NULL
    ) = 0,
    'STOP: Existing target has duplicate keys or invalid required fields.'
)
FROM {{ this }}
-- pondolens:statement --
-- Prevent an existing ID from being assigned another definition.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing indicator ID is assigned to a different definition.'
)
FROM {{ this }} t
JOIN dim_indicator_seed s
    ON t.indicator_id = s.indicator_id
WHERE NOT (t.measure_type <=> s.measure_type)
-- pondolens:statement --
-- Prevent an existing definition from receiving a different ID.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing definition is assigned to a different indicator ID.'
)
FROM {{ this }} t
JOIN dim_indicator_seed s
    ON t.measure_type = s.measure_type
WHERE t.indicator_id <> s.indicator_id
-- pondolens:statement --
-- ============================================================
-- 6. LOAD THE DIMENSION
-- Unchanged rows retain processed_at.
-- Existing IDs and measure_type are not overwritten.
-- ============================================================

MERGE INTO {{ this }} t
USING dim_indicator_seed s
ON t.indicator_id = s.indicator_id

WHEN MATCHED AND (
       NOT (t.indicator <=> s.indicator)
    OR NOT (t.unit <=> s.unit)
)
THEN UPDATE SET
    t.indicator = s.indicator,
    t.unit = s.unit,
    t.processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN INSERT (
    indicator_id,
    indicator,
    measure_type,
    unit,
    processed_at
)
VALUES (
    s.indicator_id,
    s.indicator,
    s.measure_type,
    s.unit,
    CURRENT_TIMESTAMP()
)
-- pondolens:statement --
-- ============================================================
-- 7. VALIDATE ALL 19 PERSISTED DEFINITIONS
-- Additional future definitions are not deleted.
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 19
    AND COUNT_IF(
        t.indicator_id IS NULL
        OR NOT (t.indicator <=> s.indicator)
        OR NOT (t.measure_type <=> s.measure_type)
        OR NOT (t.unit <=> s.unit)
        OR t.processed_at IS NULL
    ) = 0,
    'STOP: Persisted dimension does not match all 19 approved definitions.'
)
FROM dim_indicator_seed s
LEFT JOIN {{ this }} t
    ON s.indicator_id = t.indicator_id
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT indicator_id)
    AND COUNT(*) = COUNT(DISTINCT measure_type),
    'STOP: Duplicate IDs or definitions after MERGE.'
)
FROM {{ this }}
-- pondolens:statement --
-- ============================================================
-- 8. REVIEW SAVED OUTPUT
-- ============================================================

SELECT *
FROM {{ this }}
ORDER BY indicator_id
-- pondolens:statement --
SELECT
    indicator,
    COUNT(*) AS definition_count
FROM {{ this }}
GROUP BY indicator
ORDER BY indicator
