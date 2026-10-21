{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}
CREATE OR REPLACE TEMP VIEW dbt_dim_location_candidate AS
WITH all_locations AS (

    -- GRDP locations
    SELECT
        UPPER(TRIM(region_code)) AS location_code,
        TRIM(region_name) AS location,
        LOWER(TRIM(geographic_level)) AS geographic_level
    FROM {{ ref('grdp_per_capita') }}
    WHERE region_name IS NOT NULL

    UNION ALL

    -- Unemployment locations
    SELECT
        UPPER(TRIM(region_code)) AS location_code,
        TRIM(region_name) AS location,
        'region' AS geographic_level
    FROM {{ ref('unemployment_rate') }}
    WHERE region_name IS NOT NULL

    UNION ALL

    -- Central Office and Nationwide from appropriations
    SELECT
        UPPER(TRIM(region_code)) AS location_code,
        TRIM(region_name) AS location,
        CASE
            WHEN UPPER(TRIM(region_code)) = 'CO'
                THEN 'office'
            WHEN UPPER(TRIM(region_code)) = 'NW'
                THEN 'national'
        END AS geographic_level
    FROM {{ ref('regional_appropriations') }}
    WHERE UPPER(TRIM(region_code)) IN ('CO', 'NW')
),

standardized_locations AS (
    SELECT
        CASE
            WHEN UPPER(TRIM(location)) = 'PHILIPPINES'
                THEN 'PHL'
            WHEN UPPER(TRIM(location)) = 'CENTRAL OFFICE'
                THEN 'CO'
            WHEN UPPER(TRIM(location)) = 'NATIONWIDE'
                THEN 'NW'
            ELSE REGEXP_REPLACE(
                UPPER(TRIM(location_code)),
                '[^A-Z0-9]',
                ''
            )
        END AS location_code,

        CASE
            WHEN UPPER(TRIM(location)) = 'PHILIPPINES'
                THEN 'Philippines'
            WHEN UPPER(TRIM(location)) = 'CENTRAL OFFICE'
                THEN 'Central Office'
            WHEN UPPER(TRIM(location)) = 'NATIONWIDE'
                THEN 'Nationwide'
            ELSE TRIM(location)
        END AS location,

        CASE
            WHEN UPPER(TRIM(location_code)) = 'CO'
                THEN 'office'
            WHEN UPPER(TRIM(location_code)) = 'NW'
                THEN 'national'
            WHEN UPPER(TRIM(location)) = 'PHILIPPINES'
                THEN 'national'
            ELSE geographic_level
        END AS geographic_level

    FROM all_locations
),

-- Deduplicate locations
deduplicated_locations AS (
    SELECT
        location_code,
        location,
        geographic_level
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY location_code, geographic_level
                ORDER BY location
            ) AS rn
        FROM standardized_locations
        WHERE location_code IS NOT NULL
          AND location_code <> ''
          AND geographic_level IS NOT NULL
    )
    WHERE rn = 1
),

-- Deduplicate regional boundaries
region_geometry AS (
    SELECT
        location_code,
        psgc,
        geometry_json
    FROM (
        SELECT
            REGEXP_REPLACE(
                UPPER(TRIM(region_code)),
                '[^A-Z0-9]',
                ''
            ) AS location_code,

            adm1_psgc AS psgc,
            geometry_json,

            ROW_NUMBER() OVER (
                PARTITION BY REGEXP_REPLACE(
                    UPPER(TRIM(region_code)),
                    '[^A-Z0-9]',
                    ''
                )
                ORDER BY adm1_psgc
            ) AS rn

        FROM {{ ref('region_boundaries') }}
    )
    WHERE rn = 1
),

locations_with_geometry AS (
    SELECT
        l.location_code,
        l.location,
        l.geographic_level,

        CASE
            WHEN l.geographic_level = 'region'
                THEN g.geometry_json
            ELSE NULL
        END AS geometry_json,

        CASE
            WHEN l.geographic_level = 'region'
                THEN g.psgc
            ELSE NULL
        END AS psgc

    FROM deduplicated_locations l

    LEFT JOIN region_geometry g
        ON l.location_code = g.location_code
        AND l.geographic_level = 'region'
)

SELECT
    10000 + ROW_NUMBER() OVER (
        ORDER BY geographic_level, location_code
    ) AS location_id,

    location_code,
    location,
    geographic_level,
    geometry_json,
    psgc

FROM locations_with_geometry
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty dim_location source') FROM dbt_dim_location_candidate
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate dim_location source grain') FROM (SELECT location_code FROM dbt_dim_location_candidate GROUP BY location_code HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE TABLE IF NOT EXISTS {{ this }} USING DELTA AS SELECT *, CURRENT_TIMESTAMP() AS processed_at FROM dbt_dim_location_candidate WHERE 1 = 0
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT location_id) AND COUNT_IF(location_id IS NULL OR location_id < 10001) = 0, 'Invalid existing dim_location IDs') FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate existing dim_location grain') FROM (SELECT location_code FROM {{ this }} GROUP BY location_code HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW dbt_dim_location_mapped AS
WITH matches AS (SELECT s.*, t.location_id AS existing_id FROM dbt_dim_location_candidate s LEFT JOIN {{ this }} t ON t.location_code <=> s.location_code), last_id AS (SELECT GREATEST(COALESCE(MAX(CAST(location_id AS BIGINT)), 10000), 10000) AS last_id FROM {{ this }})
SELECT CAST(COALESCE(existing_id, last_id + ROW_NUMBER() OVER (PARTITION BY existing_id IS NULL ORDER BY location_code)) AS BIGINT) AS location_id, m.location_code, m.location, m.geographic_level, m.geometry_json, m.psgc
FROM matches m CROSS JOIN last_id
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(location_id IS NULL) = 0, 'dim_location ID allocation overflow') FROM dbt_dim_location_mapped
-- pondolens:statement --
MERGE INTO {{ this }} t USING dbt_dim_location_mapped s ON t.location_code <=> s.location_code
WHEN MATCHED AND (NOT (t.location <=> s.location) OR NOT (t.geographic_level <=> s.geographic_level) OR NOT (t.geometry_json <=> s.geometry_json) OR NOT (t.psgc <=> s.psgc)) THEN UPDATE SET t.location = s.location, t.geographic_level = s.geographic_level, t.geometry_json = s.geometry_json, t.psgc = s.psgc, t.processed_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (location_id, location_code, location, geographic_level, geometry_json, psgc, processed_at) VALUES (s.location_id, s.location_code, s.location, s.geographic_level, s.geometry_json, s.psgc, CURRENT_TIMESTAMP())
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'dim_location differs from prepared source') FROM (SELECT location_code, location, geographic_level, geometry_json, psgc FROM dbt_dim_location_candidate EXCEPT ALL SELECT location_code, location, geographic_level, geometry_json, psgc FROM {{ this }})
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(processed_at IS NULL) = 0, 'Missing dim_location processed_at') FROM {{ this }}
