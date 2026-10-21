{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- Region boundaries | Silver | Assigned to: Rhea
-- Run in one SQL session; stop on any error. Allow one target writer.
-- Keep Bronze and crosswalk stable during execution.
-- Scope: canonical regional identities in the current source snapshot.
-- This preserves source geometry; it does not repair topology or harmonize years.
CREATE SCHEMA IF NOT EXISTS {{ this.database }}.{{ this.schema }}
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW region_boundaries_prepared AS
SELECT
    TRIM(adm1_psgc) AS adm1_psgc,
    TRIM(adm1_en) AS source_name,
    REGEXP_REPLACE(UPPER(TRIM(adm1_en)), '[^A-Z0-9]', '') AS alias_key,
    geometry_json,
    GET_JSON_OBJECT(geometry_json, '$.type') AS geometry_type,
    GET_JSON_OBJECT(feature_json, '$.type') AS feature_type,
    GET_JSON_OBJECT(properties_json, '$.adm1_psgc') AS property_code,
    GET_JSON_OBJECT(properties_json, '$.adm1_en') AS property_name,
    GET_JSON_OBJECT(properties_json, '$.geo_level') AS property_level,
    GET_JSON_OBJECT(feature_json, '$.properties.adm1_psgc') AS feature_code,
    GET_JSON_OBJECT(feature_json, '$.properties.adm1_en') AS feature_name,
    GET_JSON_OBJECT(feature_json, '$.geometry.type') AS feature_geometry_type,
    CASE
        WHEN GET_JSON_OBJECT(geometry_json, '$.type') = 'Polygon' THEN
            ARRAY(FROM_JSON(GET_JSON_OBJECT(geometry_json, '$.coordinates'),
                'ARRAY<ARRAY<ARRAY<DOUBLE>>>'))
        WHEN GET_JSON_OBJECT(geometry_json, '$.type') = 'MultiPolygon' THEN
            FROM_JSON(GET_JSON_OBJECT(geometry_json, '$.coordinates'),
                'ARRAY<ARRAY<ARRAY<ARRAY<DOUBLE>>>>')
    END AS polygons,
    CASE
        WHEN GET_JSON_OBJECT(feature_json, '$.geometry.type') = 'Polygon' THEN
            ARRAY(FROM_JSON(GET_JSON_OBJECT(feature_json, '$.geometry.coordinates'),
                'ARRAY<ARRAY<ARRAY<DOUBLE>>>'))
        WHEN GET_JSON_OBJECT(feature_json, '$.geometry.type') = 'MultiPolygon' THEN
            FROM_JSON(GET_JSON_OBJECT(feature_json, '$.geometry.coordinates'),
                'ARRAY<ARRAY<ARRAY<ARRAY<DOUBLE>>>>')
    END AS feature_polygons,
    _rescued_data
FROM {{ source('bronze', 'region_boundaries') }}
-- pondolens:statement --
-- Completeness, JSON-field consistency, and coordinate structure.
SELECT ASSERT_TRUE(
    COUNT(*) > 0 AND COUNT_IF(
        NULLIF(adm1_psgc, '') IS NULL OR NULLIF(source_name, '') IS NULL
        OR geometry_type IS NULL OR geometry_type NOT IN ('Polygon', 'MultiPolygon')
        OR feature_type IS NULL OR feature_type <> 'Feature'
        OR NOT (adm1_psgc <=> TRIM(property_code))
        OR NOT (source_name <=> TRIM(property_name))
        OR NOT (adm1_psgc <=> TRIM(feature_code))
        OR NOT (source_name <=> TRIM(feature_name))
        OR property_level IS NULL OR UPPER(TRIM(property_level)) <> 'REG'
        OR NOT (geometry_type <=> feature_geometry_type)
        OR polygons IS NULL OR SIZE(polygons) = 0
        OR NOT (polygons <=> feature_polygons)
        OR EXISTS(polygons, polygon -> polygon IS NULL OR SIZE(polygon) = 0
            OR EXISTS(polygon, ring -> ring IS NULL OR SIZE(ring) < 4
                OR NOT (TRY_ELEMENT_AT(ring, 1) <=> TRY_ELEMENT_AT(ring, -1))
                OR EXISTS(ring, point -> point IS NULL OR SIZE(point) NOT IN (2, 3)
                    OR EXISTS(point, v -> v IS NULL OR ISNAN(v)
                        OR ABS(v) = CAST('Infinity' AS DOUBLE))
                    OR TRY_ELEMENT_AT(point, 1) NOT BETWEEN -180 AND 180
                    OR TRY_ELEMENT_AT(point, 2) NOT BETWEEN -90 AND 90)))
        OR NULLIF(TRIM(_rescued_data), '') IS NOT NULL
    ) = 0,
    'Boundary input failed: review identifiers, JSON consistency, coordinates or rescued data.'
)
FROM region_boundaries_prepared
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT adm1_psgc)
    AND COUNT(*) = COUNT(DISTINCT alias_key),
    'Duplicate boundary source identifiers or normalized names.'
)
FROM region_boundaries_prepared
-- pondolens:statement --
-- Map identities only. No boundary effective date has been verified.
CREATE OR REPLACE TEMP VIEW region_boundaries_lookup AS
SELECT DISTINCT
    REGEXP_REPLACE(UPPER(TRIM(source_region)), '[^A-Z0-9]', '') AS alias_key,
    UPPER(TRIM(region_code)) AS region_code,
    TRIM(region_name) AS region_name
FROM {{ ref('shared_region_crosswalk') }}
WHERE LOWER(TRIM(geographic_level)) = 'region'
  AND NULLIF(TRIM(source_region), '') IS NOT NULL
  AND NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL
  AND UPPER(TRIM(region_code)) NOT IN ('PHL', 'CO', 'NW')
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Conflicting boundary crosswalk aliases.')
FROM (
    SELECT alias_key FROM region_boundaries_lookup
    GROUP BY alias_key HAVING COUNT(*) > 1
)
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW region_boundaries_stage AS
SELECT c.region_code, c.region_name, p.adm1_psgc,
    p.geometry_type, p.geometry_json
FROM region_boundaries_prepared p
LEFT JOIN region_boundaries_lookup c ON p.alias_key = c.alias_key
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = (SELECT COUNT(*) FROM region_boundaries_prepared)
    AND COUNT(*) = COUNT(DISTINCT region_code)
    AND COUNT(*) = COUNT(DISTINCT adm1_psgc)
    AND COUNT_IF(region_code IS NULL OR region_name IS NULL) = 0,
    'Boundary mapping failed: unmapped, repeated or multiplied regions.'
)
FROM region_boundaries_stage
-- pondolens:statement --
CREATE TABLE IF NOT EXISTS {{ this }} (
    region_code STRING NOT NULL,
    region_name STRING NOT NULL,
    adm1_psgc STRING NOT NULL,
    geometry_type STRING NOT NULL,
    geometry_json STRING NOT NULL,
    processed_at TIMESTAMP NOT NULL
)
USING DELTA
COMMENT 'Current source regional boundary snapshot. Canonical identity mapping only; CRS, topology and effective date require verification before production spatial use.'
-- pondolens:statement --
-- Existing target must have one record per canonical code and source identifier.
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT region_code)
    AND COUNT(*) = COUNT(DISTINCT adm1_psgc)
    AND COALESCE(COUNT_IF(
        NULLIF(TRIM(region_code), '') IS NULL
        OR region_code <> UPPER(TRIM(region_code))
        OR NULLIF(TRIM(region_name), '') IS NULL
        OR NULLIF(TRIM(adm1_psgc), '') IS NULL
        OR geometry_type IS NULL OR geometry_type NOT IN ('Polygon', 'MultiPolygon')
        OR NULLIF(TRIM(geometry_json), '') IS NULL OR processed_at IS NULL
    ), 0) = 0,
    'Invalid existing boundary target; review keys and required fields.'
)
FROM {{ this }}
-- pondolens:statement --
-- A source identifier moving between canonical codes requires explicit review.
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Source boundary ID is already assigned to another region code.')
FROM region_boundaries_stage s
JOIN {{ this }} t
  ON s.adm1_psgc = t.adm1_psgc AND s.region_code <> t.region_code
-- pondolens:statement --
MERGE INTO {{ this }} AS t
USING region_boundaries_stage AS s
ON t.region_code = s.region_code
WHEN MATCHED AND NOT (
    t.region_name <=> s.region_name AND t.adm1_psgc <=> s.adm1_psgc
    AND t.geometry_type <=> s.geometry_type AND t.geometry_json <=> s.geometry_json
) THEN UPDATE SET
    t.region_name = s.region_name,
    t.adm1_psgc = s.adm1_psgc,
    t.geometry_type = s.geometry_type,
    t.geometry_json = s.geometry_json,
    t.processed_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
    region_code, region_name, adm1_psgc, geometry_type, geometry_json, processed_at
) VALUES (
    s.region_code, s.region_name, s.adm1_psgc, s.geometry_type, s.geometry_json, CURRENT_TIMESTAMP()
)
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Loaded boundaries differ from the validated stage.')
FROM region_boundaries_stage s
LEFT JOIN {{ this }} t ON s.region_code = t.region_code
WHERE t.region_code IS NULL
   OR NOT (s.region_name <=> t.region_name)
   OR NOT (s.adm1_psgc <=> t.adm1_psgc)
   OR NOT (s.geometry_type <=> t.geometry_type)
   OR NOT (s.geometry_json <=> t.geometry_json)
-- pondolens:statement --
SELECT COUNT(*) AS total_rows,
    COUNT(DISTINCT region_code) AS unique_regions,
    COUNT(DISTINCT adm1_psgc) AS unique_source_codes,
    COUNT_IF(geometry_type = 'Polygon') AS polygon_rows,
    COUNT_IF(geometry_type = 'MultiPolygon') AS multipolygon_rows
FROM {{ this }}
