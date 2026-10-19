-- Poverty Incidence: Bronze profiling
-- Run in one Databricks SQL session. Only temporary views are created.
-- Source records and the shared crosswalk remain unchanged.

DESCRIBE TABLE pondolens.dev_bronze.poverty_incidence;

CREATE OR REPLACE TEMP VIEW poverty_profile AS
SELECT *,
    TRY_CAST(TRIM(year) AS INT) AS parsed_year,
    NULLIF(UPPER(TRIM(region)), '') AS region_key,
    NULLIF(UPPER(TRIM(province)), '') AS province_key,
    NULLIF(UPPER(TRIM(reference_unit)), '') AS indicator_key,
    TRY_CAST(TRIM(poverty_incidence_estimate) AS DECIMAL(30, 10)) AS estimate,
    TRY_CAST(TRIM(poverty_incidence_confidence_lower) AS DECIMAL(30, 10)) AS lower_bound,
    TRY_CAST(TRIM(poverty_incidence_confidence_upper) AS DECIMAL(30, 10)) AS upper_bound,
    CASE
        WHEN UPPER(TRIM(region)) = 'PHILIPPINES'
             AND NULLIF(TRIM(province), '') IS NULL THEN 'national_candidate'
        WHEN NULLIF(TRIM(province), '') IS NOT NULL THEN 'subregional_candidate'
        WHEN NULLIF(TRIM(region), '') IS NOT NULL THEN 'regional_candidate'
        ELSE 'review'
    END AS geographic_level
FROM pondolens.dev_bronze.poverty_incidence;

-- 1. Completeness.
SELECT COUNT(*) AS total_rows,
    COUNT(DISTINCT _source_file) AS source_files,
    COUNT_IF(NULLIF(TRIM(year), '') IS NULL) AS missing_years,
    COUNT_IF(NULLIF(TRIM(region), '') IS NULL) AS missing_regions,
    COUNT_IF(NULLIF(TRIM(reference_unit), '') IS NULL) AS missing_indicator_labels,
    COUNT_IF(NULLIF(TRIM(poverty_incidence_estimate), '') IS NULL) AS missing_estimates,
    COUNT_IF(NULLIF(TRIM(annual_poverty_threshold_per_capita), '') IS NULL) AS missing_thresholds,
    COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows
FROM poverty_profile;

-- 2. Years, indicators, and geography.
SELECT year, source_page, reference_unit, geographic_level,
    COUNT(*) AS row_count, COUNT(DISTINCT region) AS distinct_region_labels
FROM poverty_profile
GROUP BY year, source_page, reference_unit, geographic_level
ORDER BY year, reference_unit, geographic_level;

SELECT region, region_name, reference_unit, notes,
    COLLECT_SET(year) AS available_years, COUNT(*) AS row_count
FROM poverty_profile
WHERE province_key IS NULL
GROUP BY region, region_name, reference_unit, notes
ORDER BY region, reference_unit;

SELECT year, COUNT(*) AS row_count
FROM poverty_profile
WHERE year IS NULL OR NOT (TRIM(year) RLIKE '^[0-9]{4}$')
   OR parsed_year NOT IN (2021, 2023, 2025)
GROUP BY year;

-- 3. Numeric measures. Dash CV markers are reported separately from missing values.
CREATE OR REPLACE TEMP VIEW poverty_numeric_profile AS
SELECT year, measure, NULLIF(TRIM(raw_value), '') AS raw_value,
    TRY_CAST(TRIM(raw_value) AS DECIMAL(30, 10)) AS numeric_value
FROM poverty_profile
LATERAL VIEW STACK(
    6,
    'threshold', annual_poverty_threshold_per_capita,
    'estimate', poverty_incidence_estimate,
    'coefficient_of_variation', poverty_incidence_coeff_var,
    'standard_error', poverty_incidence_standard_error,
    'confidence_lower', poverty_incidence_confidence_lower,
    'confidence_upper', poverty_incidence_confidence_upper
) m AS measure, raw_value;

SELECT year, measure, COUNT(*) AS total_rows,
    COUNT_IF(raw_value IS NULL) AS missing_values,
    COUNT_IF(raw_value IS NOT NULL AND numeric_value IS NULL) AS nonnumeric_values,
    COUNT_IF(measure = 'coefficient_of_variation' AND raw_value = '-') AS dash_cv_markers,
    COUNT_IF(numeric_value < 0) AS negative_values,
    COUNT_IF(measure = 'estimate' AND numeric_value > 100) AS estimates_above_100,
    MIN(numeric_value) AS minimum_value, MAX(numeric_value) AS maximum_value
FROM poverty_numeric_profile
GROUP BY year, measure
ORDER BY year, measure;

SELECT year, region, province, reference_unit, poverty_incidence_estimate,
    poverty_incidence_coeff_var, poverty_incidence_standard_error,
    poverty_incidence_confidence_lower, poverty_incidence_confidence_upper,
    notes, source_page, source_row
FROM poverty_profile
WHERE NULLIF(TRIM(poverty_incidence_coeff_var), '') IS NOT NULL
  AND TRY_CAST(TRIM(poverty_incidence_coeff_var) AS DECIMAL(30, 10)) IS NULL
ORDER BY region, province, reference_unit;

-- 4. Repeated candidate keys. National/regional totals have no province label.
SELECT TRIM(year) AS year, region_key, province_key, indicator_key,
    COUNT(*) AS row_count, COLLECT_SET(source_page) AS source_pages,
    COLLECT_SET(source_row) AS source_rows,
    COLLECT_SET(poverty_incidence_estimate) AS estimates
FROM poverty_profile
GROUP BY TRIM(year), region_key, province_key, indicator_key
HAVING COUNT(*) > 1;

-- 5. Confidence-interval ordering.
SELECT year, region, province, reference_unit, estimate, lower_bound, upper_bound
FROM poverty_profile
WHERE lower_bound > upper_bound OR estimate < lower_bound OR estimate > upper_bound
ORDER BY year, region, province;

-- 6. Threshold agreement between indicators for the same area and year.
SELECT TRIM(year) AS year, region_key, province_key,
    COUNT(DISTINCT TRY_CAST(annual_poverty_threshold_per_capita AS DECIMAL(20, 6)))
        AS distinct_thresholds
FROM poverty_profile
GROUP BY TRIM(year), region_key, province_key
HAVING COUNT(DISTINCT TRY_CAST(
    annual_poverty_threshold_per_capita AS DECIMAL(20, 6)
)) > 1;

-- 7. Strict year-valid regional mappings. No historical exception is applied here.
WITH source_regions AS (
    SELECT DISTINCT parsed_year AS year, TRIM(region) AS source_region,
        NULLIF(TRIM(region_name), '') AS source_region_name
    FROM poverty_profile
    WHERE geographic_level = 'regional_candidate'
), crosswalk AS (
    SELECT DISTINCT UPPER(TRIM(source_region)) AS alias,
        UPPER(TRIM(region_name)) AS canonical_name,
        region_code, region_name, valid_from_year, valid_to_year
    FROM pondolens.dev_silver.shared_region_crosswalk
    WHERE LOWER(TRIM(geographic_level)) = 'region'
)
SELECT s.year, s.source_region, s.source_region_name,
    COLLECT_SET(NAMED_STRUCT('region_code', c.region_code, 'region_name', c.region_name))
        FILTER (WHERE c.region_code IS NOT NULL AND c.region_name IS NOT NULL) AS mappings,
    COUNT(DISTINCT STRUCT(c.region_code, c.region_name))
        FILTER (WHERE c.region_code IS NOT NULL AND c.region_name IS NOT NULL) AS mapping_count
FROM source_regions s
LEFT JOIN crosswalk c
    ON s.year BETWEEN c.valid_from_year AND c.valid_to_year
   AND (
       UPPER(s.source_region) = c.alias
       OR UPPER(s.source_region) = c.canonical_name
       OR UPPER(s.source_region_name) = c.alias
       OR UPPER(s.source_region_name) = c.canonical_name
   )
GROUP BY s.year, s.source_region, s.source_region_name
ORDER BY s.year, s.source_region;

-- 8. Required lineage.
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
FROM poverty_profile
GROUP BY _source_file, _run_id;
