-- Unemployment Rate: Bronze profiling
-- Run in one Databricks SQL session. Source tables are unchanged.
-- Snapshot results are documented in findings.md.

DESCRIBE TABLE pondolens.dev_bronze.unemployment_rate;

CREATE OR REPLACE TEMP VIEW unemployment_profile AS
SELECT *,
    TRY_CAST(TRIM(year) AS DECIMAL(20, 6)) AS parsed_year,
    TRY_CAST(TRIM(value) AS DECIMAL(30, 12)) AS numeric_value,
    TRY_CAST(TRIM(standard_error) AS DECIMAL(30, 12)) AS numeric_se,
    TRY_CAST(TRIM(coefficient_of_variation_percent) AS DECIMAL(30, 12)) AS numeric_cv
FROM pondolens.dev_bronze.unemployment_rate;

-- Overall completeness and ingestion rescue payloads.
SELECT COUNT(*) AS total_rows,
    COUNT(DISTINCT _source_file) AS source_files,
    COUNT_IF(NULLIF(TRIM(region), '') IS NULL) AS missing_regions,
    COUNT_IF(NULLIF(TRIM(geographic_name), '') IS NULL) AS missing_geographic_names,
    COUNT_IF(NULLIF(TRIM(indicator), '') IS NULL) AS missing_indicators,
    COUNT_IF(NULLIF(TRIM(year), '') IS NULL) AS missing_years,
    COUNT_IF(NULLIF(TRIM(value), '') IS NULL) AS missing_values,
    COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows
FROM unemployment_profile;

-- Year parsing must preserve whole years.
SELECT year, COUNT(*) AS row_count
FROM unemployment_profile
WHERE parsed_year IS NULL OR parsed_year <> FLOOR(parsed_year)
   OR NOT (TRIM(year) RLIKE '^[0-9]{4}([.]0+)?$')
GROUP BY year;

SELECT year, indicator, unit, geographic_level, frequency, estimate_status,
    COUNT(*) AS row_count,
    COUNT(DISTINCT geographic_name) AS distinct_locations
FROM unemployment_profile
GROUP BY year, indicator, unit, geographic_level, frequency, estimate_status
ORDER BY year, indicator, geographic_level, estimate_status;

SELECT source_name, source_page, source_table, table_version,
    _source_file, _source_sheet, COUNT(*) AS row_count
FROM unemployment_profile
GROUP BY source_name, source_page, source_table, table_version,
    _source_file, _source_sheet
ORDER BY table_version;

-- Missing values and source markers remain visible.
SELECT year, region, geographic_name, geographic_level, indicator, unit,
    value, value_source_marker, estimate_status, table_version, source_cell
FROM unemployment_profile
WHERE NULLIF(TRIM(value), '') IS NULL OR numeric_value IS NULL
ORDER BY year, region, geographic_name, indicator;

SELECT year, indicator, unit, COUNT(*) AS total_rows,
    COUNT_IF(NULLIF(TRIM(value), '') IS NULL) AS missing_values,
    COUNT_IF(NULLIF(TRIM(value), '') IS NOT NULL AND numeric_value IS NULL)
        AS invalid_numeric_values,
    COUNT_IF(numeric_value < 0) AS negative_values,
    COUNT_IF(LOWER(TRIM(indicator)) = 'unemployment rate'
        AND numeric_value > 100) AS rates_above_100,
    COUNT_IF(NULLIF(TRIM(standard_error), '') IS NOT NULL AND numeric_se IS NULL)
        AS invalid_standard_errors,
    COUNT_IF(numeric_se < 0) AS negative_standard_errors,
    COUNT_IF(NULLIF(TRIM(coefficient_of_variation_percent), '') IS NOT NULL
        AND numeric_cv IS NULL) AS invalid_cv_values,
    COUNT_IF(numeric_cv < 0) AS negative_cv_values,
    MIN(numeric_value) AS minimum_value, MAX(numeric_value) AS maximum_value
FROM unemployment_profile
GROUP BY year, indicator, unit
ORDER BY year, indicator;

-- Within-version duplicates; parent region is part of the geography key.
SELECT year, region, geographic_name, geographic_level, indicator, unit,
    frequency, estimate_status, table_version, COUNT(*) AS row_count,
    COLLECT_SET(value) AS recorded_values,
    COLLECT_SET(source_cell) AS source_cells
FROM unemployment_profile
GROUP BY year, region, geographic_name, geographic_level, indicator, unit,
    frequency, estimate_status, table_version
HAVING COUNT(*) > 1;

-- Compare regional estimates before applying a version-selection rule.
SELECT year, region, value, standard_error, coefficient_of_variation_percent,
    estimate_status, table_version
FROM unemployment_profile
WHERE LOWER(TRIM(geographic_level)) = 'region'
  AND LOWER(TRIM(indicator)) = 'unemployment rate'
ORDER BY year, UPPER(TRIM(region)), estimate_status;

-- Collapse equivalent crosswalk rows, not source records.
CREATE OR REPLACE TEMP VIEW unemployment_aliases AS
SELECT DISTINCT UPPER(TRIM(source_region)) AS alias,
    region_code, region_name, valid_from_year, valid_to_year
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE LOWER(TRIM(geographic_level)) = 'region'
  AND NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL;

CREATE OR REPLACE TEMP VIEW unemployment_mapping AS
SELECT s.year, s.source_region,
    COLLECT_SET(NAMED_STRUCT(
        'region_code', c.region_code, 'region_name', c.region_name
    )) FILTER (WHERE c.region_code IS NOT NULL) AS mappings
FROM (
    SELECT DISTINCT CAST(parsed_year AS INT) AS year, TRIM(region) AS source_region
    FROM unemployment_profile
    WHERE LOWER(TRIM(geographic_level)) = 'region'
      AND parsed_year = FLOOR(parsed_year)
) s
LEFT JOIN unemployment_aliases c
    ON UPPER(s.source_region) = c.alias
   AND s.year BETWEEN c.valid_from_year AND c.valid_to_year
GROUP BY s.year, s.source_region;

SELECT *, SIZE(mappings) AS mapping_count
FROM unemployment_mapping
ORDER BY year, source_region;

-- Candidate selection only: no Silver table is created.
CREATE OR REPLACE TEMP VIEW unemployment_selected AS
SELECT p.*, ELEMENT_AT(m.mappings, 1).region_code AS mapped_region_code,
    SIZE(m.mappings) AS mapping_count
FROM unemployment_profile p
LEFT JOIN unemployment_mapping m
    ON CAST(p.parsed_year AS INT) = m.year
   AND TRIM(p.region) = m.source_region
WHERE LOWER(TRIM(p.indicator)) = 'unemployment rate'
  AND LOWER(TRIM(p.geographic_level)) = 'region'
  AND LOWER(TRIM(p.frequency)) = 'annual'
  AND (
      (p.parsed_year = 2021 AND LOWER(TRIM(p.estimate_status)) = 'not specified')
      OR (p.parsed_year BETWEEN 2022 AND 2024
          AND LOWER(TRIM(p.estimate_status)) = 'final')
      OR (p.parsed_year = 2025 AND LOWER(TRIM(p.estimate_status)) = 'preliminary')
  );

SELECT CAST(parsed_year AS INT) AS year, estimate_status,
    COUNT(*) AS selected_rows,
    COUNT(DISTINCT mapped_region_code) AS unique_regions,
    COUNT_IF(numeric_value IS NULL) AS missing_rates,
    COUNT_IF(COALESCE(mapping_count, 0) <> 1) AS invalid_mappings,
    MIN(numeric_value) AS minimum_rate, MAX(numeric_value) AS maximum_rate
FROM unemployment_selected
GROUP BY parsed_year, estimate_status
ORDER BY year;

-- Explicit post-mapping duplicate check: no source DISTINCT.
SELECT CAST(parsed_year AS INT) AS year, mapped_region_code,
    COUNT(*) AS row_count
FROM unemployment_selected
GROUP BY parsed_year, mapped_region_code
HAVING COUNT(*) > 1;

SELECT _source_file, _run_id, COUNT(*) AS row_count,
    COUNT_IF(
        NULLIF(TRIM(_drive_file_id), '') IS NULL
        OR NULLIF(TRIM(_source_file), '') IS NULL
        OR NULLIF(TRIM(_landing_file), '') IS NULL
        OR NULLIF(TRIM(_content_hash), '') IS NULL
        OR NULLIF(TRIM(_dataset_hash), '') IS NULL
        OR NULLIF(TRIM(_run_id), '') IS NULL
        OR _ingested_at IS NULL
    ) AS incomplete_lineage_rows,
    MIN(_ingested_at) AS earliest_ingestion,
    MAX(_ingested_at) AS latest_ingestion
FROM unemployment_profile
GROUP BY _source_file, _run_id;
