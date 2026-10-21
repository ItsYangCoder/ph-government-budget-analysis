-- Dataset: region_boundaries
-- Table: pondolens.dev_bronze.region_boundaries
-- Owner: Rhea Alum
-- Scope: active
-- Execute the complete file in one Databricks SQL session.
-- Persistent tables are read-only; session TEMP VIEWs are allowed.
-- Evidence and unresolved checks: findings.md. Column definitions: data_dictionary.md.

-- Region boundaries | Bronze profiling
-- Assigned to: Rhea Alum
-- Run in order in one SQL session. Persistent tables are read-only.
-- Structure/range checks do not establish CRS, topology, or reference date.
DESCRIBE TABLE pondolens.dev_bronze.region_boundaries;

-- 1. Completeness and uniqueness.
SELECT COUNT(*) AS total_rows,
    COUNT(DISTINCT TRIM(adm1_psgc)) AS distinct_codes,
    COUNT(DISTINCT UPPER(TRIM(adm1_en))) AS distinct_names,
    COUNT_IF(NULLIF(TRIM(adm1_psgc), '') IS NULL) AS missing_codes,
    COUNT_IF(NULLIF(TRIM(adm1_en), '') IS NULL) AS missing_names,
    COUNT_IF(NULLIF(TRIM(geometry_json), '') IS NULL) AS missing_geometry,
    COUNT_IF(NULLIF(TRIM(properties_json), '') IS NULL) AS missing_properties,
    COUNT_IF(NULLIF(TRIM(feature_json), '') IS NULL) AS missing_features,
    COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows
FROM pondolens.dev_bronze.region_boundaries;

SELECT TRIM(adm1_psgc) AS adm1_psgc, COUNT(*) AS row_count
FROM pondolens.dev_bronze.region_boundaries
GROUP BY TRIM(adm1_psgc) HAVING COUNT(*) > 1;

SELECT UPPER(TRIM(adm1_en)) AS region_name, COUNT(*) AS row_count
FROM pondolens.dev_bronze.region_boundaries
GROUP BY UPPER(TRIM(adm1_en)) HAVING COUNT(*) > 1;

SELECT adm1_psgc, adm1_en,
    GET_JSON_OBJECT(geometry_json, '$.type') AS geometry_type,
    GET_JSON_OBJECT(feature_json, '$.type') AS feature_type,
    LENGTH(geometry_json) AS geometry_text_length
FROM pondolens.dev_bronze.region_boundaries ORDER BY adm1_en;

SELECT adm1_psgc, adm1_en, properties_json, _source_file, _source_modified_at
FROM pondolens.dev_bronze.region_boundaries ORDER BY adm1_en;

-- 2. Consistency of extracted fields with embedded properties and type labels.
WITH inspected AS (
    SELECT *,
        GET_JSON_OBJECT(properties_json, '$.adm1_psgc') AS property_code,
        GET_JSON_OBJECT(properties_json, '$.adm1_en') AS property_name,
        GET_JSON_OBJECT(properties_json, '$.geo_level') AS property_level,
        GET_JSON_OBJECT(feature_json, '$.properties.adm1_psgc') AS feature_code,
        GET_JSON_OBJECT(feature_json, '$.properties.adm1_en') AS feature_name,
        GET_JSON_OBJECT(geometry_json, '$.type') AS geometry_type,
        GET_JSON_OBJECT(feature_json, '$.geometry.type') AS feature_geometry_type
    FROM pondolens.dev_bronze.region_boundaries
)
SELECT COUNT(*) AS total_rows,
    COUNT_IF(NOT (TRIM(adm1_psgc) <=> TRIM(property_code))) AS property_code_mismatches,
    COUNT_IF(NOT (TRIM(adm1_en) <=> TRIM(property_name))) AS property_name_mismatches,
    COUNT_IF(NOT (TRIM(adm1_psgc) <=> TRIM(feature_code))) AS feature_code_mismatches,
    COUNT_IF(NOT (TRIM(adm1_en) <=> TRIM(feature_name))) AS feature_name_mismatches,
    COUNT_IF(property_level IS NULL OR UPPER(TRIM(property_level)) <> 'REG') AS unexpected_property_levels,
    COUNT_IF(geometry_type IS NULL OR geometry_type NOT IN ('Polygon', 'MultiPolygon')) AS unsupported_geometry_types,
    COUNT_IF(NOT (geometry_type <=> feature_geometry_type)) AS geometry_type_mismatches
FROM inspected;

-- 3. Normalize coordinate nesting for structural profiling only.
CREATE OR REPLACE TEMP VIEW boundary_polygons_profile AS
WITH parsed AS (
    SELECT adm1_psgc, adm1_en,
        GET_JSON_OBJECT(geometry_json, '$.type') AS geometry_type,
        GET_JSON_OBJECT(geometry_json, '$.coordinates') AS coordinates_json
    FROM pondolens.dev_bronze.region_boundaries
)
SELECT adm1_psgc, adm1_en, geometry_type,
    CASE
        WHEN geometry_type = 'Polygon' THEN ARRAY(FROM_JSON(
            coordinates_json, 'ARRAY<ARRAY<ARRAY<DOUBLE>>>'
        ))
        WHEN geometry_type = 'MultiPolygon' THEN FROM_JSON(
            coordinates_json, 'ARRAY<ARRAY<ARRAY<ARRAY<DOUBLE>>>>'
        )
    END AS polygons
FROM parsed;

SELECT adm1_psgc, adm1_en, geometry_type, SIZE(polygons) AS polygon_count,
    CASE WHEN polygons IS NULL THEN 'UNPARSEABLE'
         WHEN SIZE(polygons) = 0 THEN 'EMPTY'
         WHEN EXISTS(polygons, p -> p IS NULL OR SIZE(p) = 0) THEN 'REVIEW'
         ELSE 'PARSED' END AS coordinate_structure_status
FROM boundary_polygons_profile ORDER BY adm1_en;

CREATE OR REPLACE TEMP VIEW boundary_rings_profile AS
SELECT adm1_psgc, adm1_en, polygon_index, ring_index, ring
FROM boundary_polygons_profile
LATERAL VIEW POSEXPLODE(polygons) p AS polygon_index, polygon
LATERAL VIEW POSEXPLODE(polygon) r AS ring_index, ring;

SELECT COUNT(*) AS total_rings,
    COUNT_IF(ring IS NULL OR SIZE(ring) < 4) AS invalid_ring_lengths,
    COUNT_IF(NOT (TRY_ELEMENT_AT(ring, 1) <=> TRY_ELEMENT_AT(ring, -1))) AS unclosed_rings,
    COUNT_IF(EXISTS(ring, point -> point IS NULL OR SIZE(point) < 2
        OR EXISTS(point, coordinate -> coordinate IS NULL OR ISNAN(coordinate)
            OR ABS(coordinate) = CAST('Infinity' AS DOUBLE)))) AS rings_with_invalid_positions
FROM boundary_rings_profile;

WITH points AS (
    SELECT adm1_psgc, adm1_en, point
    FROM boundary_rings_profile LATERAL VIEW EXPLODE(ring) p AS point
), coordinates AS (
    SELECT *, TRY_ELEMENT_AT(point, 1) AS longitude,
        TRY_ELEMENT_AT(point, 2) AS latitude FROM points
)
SELECT COUNT(*) AS total_positions,
    COUNT_IF(longitude IS NULL OR latitude IS NULL
        OR ISNAN(longitude) OR ISNAN(latitude)
        OR longitude NOT BETWEEN -180 AND 180
        OR latitude NOT BETWEEN -90 AND 90) AS invalid_coordinates,
    MIN(longitude) AS minimum_longitude, MAX(longitude) AS maximum_longitude,
    MIN(latitude) AS minimum_latitude, MAX(latitude) AS maximum_latitude
FROM coordinates;

-- 4. Region identity matching only; reference date is not yet verified.
-- Collapse equivalent aliases before counting distinct canonical mappings.
WITH boundaries AS (
    SELECT adm1_psgc, adm1_en,
        REGEXP_REPLACE(UPPER(TRIM(adm1_en)), '[^A-Z0-9]', '') AS region_key
    FROM pondolens.dev_bronze.region_boundaries
), crosswalk AS (
    SELECT DISTINCT
        REGEXP_REPLACE(UPPER(TRIM(source_region)), '[^A-Z0-9]', '') AS region_key,
        UPPER(TRIM(region_code)) AS region_code, TRIM(region_name) AS region_name
    FROM pondolens.dev_silver.shared_region_crosswalk
    WHERE LOWER(TRIM(geographic_level)) = 'region'
      AND NULLIF(TRIM(source_region), '') IS NOT NULL
      AND NULLIF(TRIM(region_code), '') IS NOT NULL
      AND NULLIF(TRIM(region_name), '') IS NOT NULL
)
SELECT b.adm1_psgc, b.adm1_en AS source_region_name,
    COLLECT_SET(c.region_code) AS matched_codes,
    COLLECT_SET(c.region_name) AS matched_names,
    COUNT(DISTINCT STRUCT(c.region_code, c.region_name))
        FILTER (WHERE c.region_code IS NOT NULL) AS mapping_count
FROM boundaries b LEFT JOIN crosswalk c ON b.region_key = c.region_key
GROUP BY b.adm1_psgc, b.adm1_en ORDER BY b.adm1_en;

-- 5. Ingestion lineage. A NULL source_sheet is valid for GeoJSON.
SELECT _source_file, _run_id, COUNT(*) AS row_count,
    COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
        OR NULLIF(TRIM(_source_file), '') IS NULL
        OR NULLIF(TRIM(_landing_file), '') IS NULL
        OR NULLIF(TRIM(_content_hash), '') IS NULL
        OR NULLIF(TRIM(_dataset_hash), '') IS NULL
        OR NULLIF(TRIM(_run_id), '') IS NULL OR _ingested_at IS NULL) AS incomplete_lineage_rows,
    MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.region_boundaries GROUP BY _source_file, _run_id;
