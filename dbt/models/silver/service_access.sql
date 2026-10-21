{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- ============================================================
-- PondoLens | Service Access: Bronze → Silver
-- Author: Joy
-- Date: 2026-10-20
--
-- Purpose:
-- Clean, validate, and load regional PSA APIS service-access
-- observations for 2022 and 2024 into the Silver layer.
--
-- Target: {{ this }}
-- ============================================================

SET TIME ZONE 'UTC'
-- pondolens:statement --
-- ============================================================
-- 1. SELECT SOURCE RECORDS
-- National observations remain in Bronze.
-- ============================================================

CREATE OR REPLACE TEMP VIEW service_access_selected AS
SELECT
    TRIM(region) AS source_region,
    TRY_CAST(TRIM(year) AS DECIMAL(10, 2)) AS year_num,
    TRIM(indicator) AS indicator,
    TRIM(breakdown_type) AS breakdown_type,
    TRIM(breakdown_value) AS breakdown_value,
    TRY_CAST(TRIM(value) AS DECIMAL(20, 10)) AS measurement,
    TRIM(unit) AS unit,
    TRIM(country) AS country,
    _rescued_data
FROM {{ source('bronze', 'service_access') }}
WHERE TRIM(source) = 'PSA APIS'
  AND TRY_CAST(TRIM(year) AS DECIMAL(10, 2)) IN (2022, 2024)
  AND TRIM(indicator) IN (
      'At least basic drinking-water access',
      'Basic sanitation access',
      'Basic handwashing facilities'
  )
  AND (
      region IS NULL
      OR UPPER(TRIM(region)) NOT IN ('NATIONAL', 'PHILIPPINES')
  )
-- pondolens:statement --
-- ============================================================
-- 2. VALIDATE SOURCE SCOPE, VALUES, AND DENOMINATORS
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 102,
    'STOP: Expected 102 regional PSA APIS records.'
)
FROM service_access_selected
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT_IF(
        country IS NULL
        OR LOWER(country) <> 'philippines'
        OR source_region IS NULL
        OR source_region = ''
        OR year_num IS NULL
        OR year_num <> FLOOR(year_num)
        OR measurement IS NULL
        OR measurement < 0
        OR measurement > 100
        OR breakdown_type IS NULL
        OR breakdown_type <> 'Total'
        OR breakdown_value IS NULL
        OR unit IS NULL

        OR (
            indicator = 'Basic handwashing facilities'
            AND (
                unit <> '% of consenting families'
                OR breakdown_value <> 'Consenting families'
            )
        )

        OR (
            indicator IN (
                'At least basic drinking-water access',
                'Basic sanitation access'
            )
            AND (
                unit <> '% of families'
                OR breakdown_value <> 'All families'
            )
        )

        OR (
            _rescued_data IS NOT NULL
            AND LOWER(TRIM(_rescued_data)) NOT IN ('', 'null')
        )
    ) = 0,
    'STOP: Invalid source value, denominator, label, or rescued data.'
)
FROM service_access_selected
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate source region/year/indicator keys.'
)
FROM (
    SELECT
        source_region,
        year_num,
        indicator
    FROM service_access_selected
    GROUP BY source_region, year_num, indicator
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 3. BUILD UNIQUE REGION MAPPING
--
-- Apply year validity FIRST.
-- Collapse identical region-code/name outputs only.
-- Conflicting outputs remain separate and fail validation.
-- ============================================================

CREATE OR REPLACE TEMP VIEW service_access_region_map AS
SELECT DISTINCT
    s.source_region,
    s.year_num,
    TRIM(c.region_code) AS region_code,
    TRIM(c.region_name) AS region_name
FROM (
    SELECT DISTINCT
        source_region,
        year_num
    FROM service_access_selected
) s
JOIN {{ ref('shared_region_crosswalk') }} c
    ON UPPER(TRIM(s.source_region))
        = UPPER(TRIM(c.source_region))
   AND s.year_num BETWEEN c.valid_from_year AND c.valid_to_year
   AND LOWER(TRIM(c.geographic_level)) IN ('region', 'regional')
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW service_access_mapping_check AS
SELECT
    s.source_region,
    s.year_num,
    COUNT(m.source_region) AS mapping_count
FROM (
    SELECT DISTINCT
        source_region,
        year_num
    FROM service_access_selected
) s
LEFT JOIN service_access_region_map m
    ON s.source_region = m.source_region
   AND s.year_num = m.year_num
GROUP BY s.source_region, s.year_num
-- pondolens:statement --
-- Diagnostic: expected to return NO ROWS.
SELECT *
FROM service_access_mapping_check
WHERE mapping_count <> 1
ORDER BY source_region, year_num
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT_IF(mapping_count <> 1) = 0,
    'STOP: Missing or conflicting region/year mapping.'
)
FROM service_access_mapping_check
-- pondolens:statement --
-- ============================================================
-- 4. BUILD CLEAN SILVER RECORDS
-- ============================================================

CREATE OR REPLACE TEMP VIEW service_access_clean AS
SELECT
    CAST(s.year_num AS INT) AS year,

    CASE s.indicator
        WHEN 'At least basic drinking-water access'
            THEN 'water'
        WHEN 'Basic sanitation access'
            THEN 'sanitation'
        WHEN 'Basic handwashing facilities'
            THEN 'hygiene'
    END AS service,

    CASE s.indicator
        WHEN 'At least basic drinking-water access'
            THEN 'at_least_basic_drinking_water_access'
        WHEN 'Basic sanitation access'
            THEN 'basic_sanitation_access'
        WHEN 'Basic handwashing facilities'
            THEN 'basic_handwashing_facilities'
    END AS service_measure,

    m.region_name,
    m.region_code,
    s.breakdown_type,
    s.breakdown_value,
    CAST(s.measurement AS DOUBLE) AS value,
    s.unit

FROM service_access_selected s
JOIN service_access_region_map m
    ON s.source_region = m.source_region
   AND s.year_num = m.year_num
-- pondolens:statement --
-- ============================================================
-- 5. VALIDATE CLEAN RECORDS AND COVERAGE
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 102
    AND COUNT_IF(
        region_code IS NULL OR region_code = ''
        OR region_name IS NULL OR region_name = ''
        OR service IS NULL
        OR service_measure IS NULL
    ) = 0,
    'STOP: Invalid canonical records or unexpected row count.'
)
FROM service_access_clean
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate clean region/year/measure keys.'
)
FROM (
    SELECT
        region_code,
        year,
        service_measure
    FROM service_access_clean
    GROUP BY region_code, year, service_measure
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 6
    AND COUNT_IF(row_count <> 17 OR region_count <> 17) = 0,
    'STOP: Expected 17 regions per measure/year across six groups.'
)
FROM (
    SELECT
        year,
        service_measure,
        COUNT(*) AS row_count,
        COUNT(DISTINCT region_code) AS region_count
    FROM service_access_clean
    GROUP BY year, service_measure
) coverage
-- pondolens:statement --
-- ============================================================
-- 6. CREATE PERSISTENT DELTA TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS {{ this }} (
    service_access_id INT NOT NULL,
    year INT NOT NULL,
    service STRING NOT NULL,
    service_measure STRING NOT NULL,
    region_name STRING NOT NULL,
    region_code STRING NOT NULL,
    breakdown_type STRING NOT NULL,
    breakdown_value STRING NOT NULL,
    value DOUBLE NOT NULL,
    unit STRING NOT NULL,
    processed_at TIMESTAMP NOT NULL
)
USING DELTA
-- pondolens:statement --
-- Validate existing target before writing.
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(service_access_id)
    AND COUNT(*) = COUNT(DISTINCT service_access_id)
    AND COUNT_IF(service_access_id < 400000001) = 0,
    'STOP: Existing target contains null, duplicate, or unexpected IDs.'
)
FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing target contains duplicate business keys.'
)
FROM (
    SELECT
        region_code,
        year,
        service_measure
    FROM {{ this }}
    GROUP BY region_code, year, service_measure
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 7. ALLOCATE IDs FOR NEW RECORDS ONLY
-- Existing IDs are preserved.
-- ============================================================

CREATE OR REPLACE TEMP VIEW service_access_new_ids AS
SELECT
    s.region_code,
    s.year,
    s.service_measure,

    CAST(
        m.max_id + ROW_NUMBER() OVER (
            ORDER BY s.region_code, s.year, s.service_measure
        )
        AS INT
    ) AS service_access_id

FROM (
    SELECT s.*
    FROM service_access_clean s
    LEFT ANTI JOIN {{ this }} t
        ON s.region_code = t.region_code
       AND s.year = t.year
       AND s.service_measure = t.service_measure
) s

CROSS JOIN (
    SELECT COALESCE(
        MAX(CAST(service_access_id AS BIGINT)),
        CAST(400000000 AS BIGINT)
    ) AS max_id
    FROM {{ this }}
) m
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW service_access_upsert AS
SELECT
    COALESCE(
        t.service_access_id,
        n.service_access_id
    ) AS service_access_id,
    s.*
FROM service_access_clean s

LEFT JOIN {{ this }} t
    ON s.region_code = t.region_code
   AND s.year = t.year
   AND s.service_measure = t.service_measure

LEFT JOIN service_access_new_ids n
    ON s.region_code = n.region_code
   AND s.year = n.year
   AND s.service_measure = n.service_measure
-- pondolens:statement --
-- ============================================================
-- 8. MERGE INTO PERSISTENT SILVER TABLE
-- Unchanged records keep their IDs and processed_at.
-- ============================================================

MERGE INTO {{ this }} t
USING service_access_upsert s
ON  t.region_code = s.region_code
AND t.year = s.year
AND t.service_measure = s.service_measure

WHEN MATCHED AND (
       NOT (t.service <=> s.service)
    OR NOT (t.region_name <=> s.region_name)
    OR NOT (t.breakdown_type <=> s.breakdown_type)
    OR NOT (t.breakdown_value <=> s.breakdown_value)
    OR NOT (t.value <=> s.value)
    OR NOT (t.unit <=> s.unit)
)
THEN UPDATE SET
    t.service = s.service,
    t.region_name = s.region_name,
    t.breakdown_type = s.breakdown_type,
    t.breakdown_value = s.breakdown_value,
    t.value = s.value,
    t.unit = s.unit,
    t.processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED THEN INSERT (
    service_access_id,
    year,
    service,
    service_measure,
    region_name,
    region_code,
    breakdown_type,
    breakdown_value,
    value,
    unit,
    processed_at
)
VALUES (
    s.service_access_id,
    s.year,
    s.service,
    s.service_measure,
    s.region_name,
    s.region_code,
    s.breakdown_type,
    s.breakdown_value,
    s.value,
    s.unit,
    CURRENT_TIMESTAMP()
)
-- pondolens:statement --
-- ============================================================
-- 9. VALIDATE PERSISTED RECORDS AGAINST CLEAN SOURCE
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 102
    AND COUNT_IF(
        t.service_access_id IS NULL
        OR NOT (t.service <=> s.service)
        OR NOT (t.region_name <=> s.region_name)
        OR NOT (t.breakdown_type <=> s.breakdown_type)
        OR NOT (t.breakdown_value <=> s.breakdown_value)
        OR NOT (t.value <=> s.value)
        OR NOT (t.unit <=> s.unit)
        OR t.processed_at IS NULL
    ) = 0,
    'STOP: Persisted records do not match the validated source.'
)
FROM service_access_clean s
LEFT JOIN {{ this }} t
    ON s.region_code = t.region_code
   AND s.year = t.year
   AND s.service_measure = t.service_measure
-- pondolens:statement --
-- ============================================================
-- 10. REVIEW FINAL OUTPUT
-- ============================================================

SELECT
    year,
    service_measure,
    unit,
    COUNT(*) AS row_count,
    COUNT(DISTINCT region_code) AS region_count,
    MIN(value) AS min_value,
    MAX(value) AS max_value
FROM {{ this }}
GROUP BY year, service_measure, unit
ORDER BY year, service_measure
-- pondolens:statement --
SELECT *
FROM {{ this }}
ORDER BY service_access_id
LIMIT 10
