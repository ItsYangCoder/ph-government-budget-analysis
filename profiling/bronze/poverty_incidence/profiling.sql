-- Poverty Incidence Profiling
-- Table: pondolens.dev_bronze.poverty_incidence
-- Notes and findings: mia_poverty_incidence_profiling_doc
-- Read-only profiling queries. Each query returns its own result table.


-- 1. DATASET UNDERSTANDING

-- 1.1 Table schema
DESCRIBE TABLE pondolens.dev_bronze.poverty_incidence;

-- 1.2 Sample rows
SELECT *
FROM pondolens.dev_bronze.poverty_incidence
LIMIT 10;

-- 1.3 Row count and coverage
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT year) AS years,
    MIN(year) AS earliest_year,
    MAX(year) AS latest_year,
    COUNT(DISTINCT region) AS region_labels_incl_national,
    COUNT(DISTINCT province) AS province_district_city_labels,
    COUNT(DISTINCT reference_unit) AS reference_units,
    COUNT(DISTINCT source_page) AS source_sheets
FROM pondolens.dev_bronze.poverty_incidence;

-- 1.4 Rows by source sheet, reference unit and year
SELECT
    source_page,
    reference_unit,
    year,
    COUNT(*) AS row_count
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY source_page, reference_unit, year
ORDER BY source_page, year;

-- 1.5 Rows by geographic level (derived from region and province)
SELECT
    CASE
        WHEN UPPER(TRIM(region)) = 'PHILIPPINES' THEN 'national'
        WHEN province IS NULL OR TRIM(province) = '' THEN 'region'
        WHEN TRIM(province) LIKE '%District' THEN 'district'
        WHEN TRIM(province) LIKE '%City' THEN 'city'
        ELSE 'province'
    END AS geographic_level,
    COUNT(*) AS row_count
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY 1
ORDER BY row_count DESC;

-- 1.6 Source file and sheets
SELECT
    source_name,
    source_page,
    COUNT(*) AS row_count,
    MIN(TRY_CAST(source_row AS INT)) AS first_excel_row,
    MAX(TRY_CAST(source_row AS INT)) AS last_excel_row
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY source_name, source_page
ORDER BY source_page;


-- 2. COMPLETENESS

-- 2.1 Null or blank values per column
SELECT
    COUNT(*) AS total_rows,
    COUNT_IF(source_page IS NULL OR TRIM(source_page) = '') AS source_page_missing,
    COUNT_IF(source_row IS NULL OR TRIM(source_row) = '') AS source_row_missing,
    COUNT_IF(year IS NULL OR TRIM(year) = '') AS year_missing,
    COUNT_IF(region IS NULL OR TRIM(region) = '') AS region_missing,
    COUNT_IF(region_name IS NULL OR TRIM(region_name) = '') AS region_name_missing,
    COUNT_IF(province IS NULL OR TRIM(province) = '') AS province_missing,
    COUNT_IF(annual_poverty_threshold_per_capita IS NULL OR TRIM(annual_poverty_threshold_per_capita) = '') AS threshold_missing,
    COUNT_IF(reference_unit IS NULL OR TRIM(reference_unit) = '') AS reference_unit_missing,
    COUNT_IF(poverty_incidence_estimate IS NULL OR TRIM(poverty_incidence_estimate) = '') AS estimate_missing,
    COUNT_IF(poverty_incidence_coeff_var IS NULL OR TRIM(poverty_incidence_coeff_var) = '') AS coeff_var_missing,
    COUNT_IF(poverty_incidence_standard_error IS NULL OR TRIM(poverty_incidence_standard_error) = '') AS standard_error_missing,
    COUNT_IF(poverty_incidence_confidence_lower IS NULL OR TRIM(poverty_incidence_confidence_lower) = '') AS ci_lower_missing,
    COUNT_IF(poverty_incidence_confidence_upper IS NULL OR TRIM(poverty_incidence_confidence_upper) = '') AS ci_upper_missing,
    COUNT_IF(notes IS NULL OR TRIM(notes) = '') AS notes_missing
FROM pondolens.dev_bronze.poverty_incidence;

-- 2.2 Where region_name and notes are blank (blank province on region rows is expected)
SELECT
    region,
    province,
    COUNT_IF(region_name IS NULL OR TRIM(region_name) = '') AS blank_region_name,
    COUNT_IF(notes IS NULL OR TRIM(notes) = '') AS blank_notes,
    COUNT(*) AS row_count
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY region, province
HAVING COUNT_IF(region_name IS NULL OR TRIM(region_name) = '') > 0
    OR COUNT_IF(notes IS NULL OR TRIM(notes) = '') > 0
ORDER BY region, province;

-- 2.3 Year coverage per region: number of areas (region + provinces) in the families sheet
SELECT
    region,
    COUNT_IF(year = 2021) AS y2021,
    COUNT_IF(year = 2023) AS y2023,
    COUNT_IF(year = 2025) AS y2025
FROM pondolens.dev_bronze.poverty_incidence
WHERE source_page = 'tab1'
GROUP BY region
ORDER BY region;

-- 2.4 Areas not present in all three years. Expected: Maguindanao del Norte and del Sur only.
SELECT
    region,
    province,
    reference_unit,
    COUNT(DISTINCT year) AS years_present,
    CONCAT_WS(', ', ARRAY_SORT(COLLECT_SET(CAST(year AS STRING)))) AS years
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY region, province, reference_unit
HAVING COUNT(DISTINCT year) < 3
ORDER BY region, province, reference_unit;


-- 3. UNIQUENESS

-- 3.1 Exact duplicate rows (data columns). Expected: no rows.
SELECT
    year,
    region,
    region_name,
    province,
    reference_unit,
    annual_poverty_threshold_per_capita,
    poverty_incidence_estimate,
    poverty_incidence_coeff_var,
    poverty_incidence_standard_error,
    poverty_incidence_confidence_lower,
    poverty_incidence_confidence_upper,
    notes,
    COUNT(*) AS duplicate_count
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY
    year,
    region,
    region_name,
    province,
    reference_unit,
    annual_poverty_threshold_per_capita,
    poverty_incidence_estimate,
    poverty_incidence_coeff_var,
    poverty_incidence_standard_error,
    poverty_incidence_confidence_lower,
    poverty_incidence_confidence_upper,
    notes
HAVING COUNT(*) > 1;

-- 3.2 Repeated business keys: year + reference unit + region + province. Expected: no rows.
SELECT
    year,
    reference_unit,
    region,
    province,
    COUNT(*) AS occurrences,
    COUNT(DISTINCT poverty_incidence_estimate) AS distinct_estimates
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY year, reference_unit, region, province
HAVING COUNT(*) > 1;

-- 3.3 Repeated source positions: sheet + Excel row + year. Expected: no rows.
SELECT
    source_page,
    source_row,
    year,
    COUNT(*) AS occurrences
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY source_page, source_row, year
HAVING COUNT(*) > 1;


-- 4. VALIDITY

-- 4.1 Parse values for profiling. Raw values are kept so the '-' marker stays visible.
CREATE OR REPLACE TEMP VIEW poverty_incidence_profile AS
SELECT
    TRY_CAST(year AS INT) AS year,
    source_page,
    TRY_CAST(source_row AS INT) AS source_row,
    CASE
        WHEN LOWER(reference_unit) LIKE '%families%' THEN 'families'
        WHEN LOWER(reference_unit) LIKE '%population%' THEN 'population'
    END AS measure,
    TRIM(region) AS region,
    TRIM(region_name) AS region_name,
    COALESCE(TRIM(province), '') AS province,
    CASE
        WHEN UPPER(TRIM(region)) = 'PHILIPPINES' THEN 'national'
        WHEN province IS NULL OR TRIM(province) = '' THEN 'region'
        WHEN TRIM(province) LIKE '%District' THEN 'district'
        WHEN TRIM(province) LIKE '%City' THEN 'city'
        ELSE 'province'
    END AS geographic_level,
    TRIM(poverty_incidence_coeff_var) AS coeff_var_raw,
    TRY_CAST(annual_poverty_threshold_per_capita AS DECIMAL(10, 2)) AS threshold_php,
    TRY_CAST(poverty_incidence_estimate AS DECIMAL(5, 2)) AS estimate_pct,
    TRY_CAST(poverty_incidence_coeff_var AS DECIMAL(5, 2)) AS coeff_var,
    TRY_CAST(poverty_incidence_standard_error AS DECIMAL(5, 2)) AS standard_error,
    TRY_CAST(poverty_incidence_confidence_lower AS DECIMAL(5, 2)) AS ci_lower,
    TRY_CAST(poverty_incidence_confidence_upper AS DECIMAL(5, 2)) AS ci_upper,
    TRIM(notes) AS notes,
    TRANSFORM(SPLIT(COALESCE(notes, ''), ','), x -> TRIM(x)) AS note_codes
FROM pondolens.dev_bronze.poverty_incidence;

-- 4.2 Parseability and ranges per year and measure
SELECT
    year,
    measure,
    COUNT(*) AS total_observations,
    COUNT(estimate_pct) AS numeric_estimates,
    COUNT_IF(coeff_var_raw = '-') AS dash_markers_in_cv,
    COUNT_IF(coeff_var IS NULL AND coeff_var_raw <> '-') AS unexpected_nonnumeric_cv,
    COUNT_IF(estimate_pct < 0 OR estimate_pct > 100) AS outside_percentage_range,
    MIN(estimate_pct) AS minimum_rate,
    MAX(estimate_pct) AS maximum_rate,
    MIN(threshold_php) AS minimum_threshold_php,
    MAX(threshold_php) AS maximum_threshold_php
FROM poverty_incidence_profile
GROUP BY year, measure
ORDER BY year, measure;

-- 4.3 Logic checks. Expected: 0 in every column.
SELECT
    COUNT(*) AS total_rows,
    COUNT_IF(year IS NULL OR year NOT IN (2021, 2023, 2025)) AS invalid_year,
    COUNT_IF(measure IS NULL) AS unknown_reference_unit,
    COUNT_IF(threshold_php IS NULL OR threshold_php <= 0) AS invalid_threshold,
    COUNT_IF(estimate_pct IS NULL) AS missing_estimate,
    COUNT_IF(estimate_pct < ci_lower OR estimate_pct > ci_upper) AS estimate_outside_ci,
    COUNT_IF(ci_lower < 0 OR ci_upper > 100) AS ci_outside_0_100,
    COUNT_IF(standard_error < 0 OR coeff_var < 0) AS negative_se_or_cv,
    COUNT_IF(coeff_var IS NULL AND estimate_pct <> 0) AS missing_cv_on_nonzero_estimate
FROM poverty_incidence_profile;

-- 4.4 Identify zero estimates and missing CVs (expected: 8 rows, all 2025, all with c/)
SELECT
    year,
    measure,
    region,
    province,
    estimate_pct,
    coeff_var_raw,
    notes
FROM poverty_incidence_profile
WHERE estimate_pct = 0
   OR coeff_var IS NULL
ORDER BY region, province, measure;

-- 4.5 Estimate status: reliability by CV (CV above 10% = use with caution)
SELECT
    geographic_level,
    COUNT_IF(coeff_var <= 10) AS reliable_cv_10_or_less,
    COUNT_IF(coeff_var > 10) AS caution_cv_over_10,
    COUNT_IF(coeff_var IS NULL) AS no_cv,
    COUNT(*) AS total_rows
FROM poverty_incidence_profile
GROUP BY geographic_level
ORDER BY total_rows DESC;

-- 4.6 Estimate status: note codes used
SELECT
    note_code,
    CASE note_code
        WHEN '1/' THEN 'Significant change 2021 to 2023'
        WHEN '2/' THEN 'Significant change 2023 to 2025'
        WHEN 'b/' THEN 'CV above 10%, use with caution'
        WHEN 'c/' THEN 'Estimate below 0.05%'
        WHEN 'r1/' THEN 'Revised: Sulu moved from BARMM to Region IX'
        WHEN 'r2/' THEN 'Revised: 63 North Cotabato barangays moved to BARMM'
        ELSE 'UNKNOWN CODE'
    END AS meaning,
    COUNT(*) AS row_count
FROM poverty_incidence_profile
LATERAL VIEW EXPLODE(note_codes) codes AS note_code
WHERE note_code <> ''
GROUP BY note_code
ORDER BY note_code;

-- 4.7 Estimate status: flags agree with the numbers. Expected: 0 mismatches.
-- b/ is set when any of the area's three years has CV > 10; c/ when any year is below 0.05%.
WITH area_status AS (
    SELECT
        *,
        MAX(coeff_var) OVER (PARTITION BY measure, region, province) > 10 AS any_year_cv_over_10,
        MIN(estimate_pct) OVER (PARTITION BY measure, region, province) < 0.05 AS any_year_below_0_05
    FROM poverty_incidence_profile
)
SELECT
    COUNT_IF(coeff_var > 10) AS rows_with_cv_over_10,
    COUNT_IF(ARRAY_CONTAINS(note_codes, 'b/')) AS rows_flagged_b,
    COUNT_IF(any_year_cv_over_10 <> ARRAY_CONTAINS(note_codes, 'b/')) AS b_flag_mismatch,
    COUNT_IF(estimate_pct = 0) AS rows_with_zero_estimate,
    COUNT_IF(ARRAY_CONTAINS(note_codes, 'c/')) AS rows_flagged_c,
    COUNT_IF(any_year_below_0_05 <> ARRAY_CONTAINS(note_codes, 'c/')) AS c_flag_mismatch
FROM area_status;

-- 4.8 Precision measures agree: CI = estimate +/- 1.96 x SE (small gaps come from rounding)
SELECT
    measure,
    COUNT(*) AS total_rows,
    MAX(GREATEST(
        ABS(ci_lower - (estimate_pct - 1.96 * standard_error)),
        ABS(ci_upper - (estimate_pct + 1.96 * standard_error))
    )) AS largest_ci_gap_pp,
    COUNT_IF(GREATEST(
        ABS(ci_lower - (estimate_pct - 1.96 * standard_error)),
        ABS(ci_upper - (estimate_pct + 1.96 * standard_error))
    ) > 0.3) AS ci_gap_over_0_3_pp
FROM poverty_incidence_profile
GROUP BY measure
ORDER BY measure;


-- 5. CONSISTENCY

-- 5.1 Region labels as stored
SELECT
    region,
    region_name,
    COUNT(*) AS row_count
FROM poverty_incidence_profile
GROUP BY region, region_name
ORDER BY region;

-- 5.2 Names that differ only by case, spacing or punctuation. Expected: no rows.
WITH names AS (
    SELECT region AS name FROM poverty_incidence_profile
    UNION ALL
    SELECT province AS name FROM poverty_incidence_profile WHERE province <> ''
)
SELECT
    UPPER(REGEXP_REPLACE(name, '[^A-Za-z0-9]', '')) AS normalized_name,
    CONCAT_WS(' | ', ARRAY_SORT(COLLECT_SET(name))) AS spellings,
    COUNT(DISTINCT name) AS variations
FROM names
GROUP BY UPPER(REGEXP_REPLACE(name, '[^A-Za-z0-9]', ''))
HAVING COUNT(DISTINCT name) > 1;

-- 5.3 Proposed team region codes and names. Expected: all MAPPED.
WITH region_ref AS (
    SELECT * FROM VALUES
        ('PHILIPPINES', 'PHL', 'Philippines'),
        ('National Capital Region', 'NCR', 'National Capital Region'),
        ('Cordillera Administrative Region', 'CAR', 'Cordillera Administrative Region'),
        ('Region I', 'I', 'Ilocos Region'),
        ('Region II', 'II', 'Cagayan Valley'),
        ('Region III', 'III', 'Central Luzon'),
        ('Region IV-A', 'IVA', 'CALABARZON'),
        ('MIMAROPA Region', 'IVB', 'MIMAROPA Region'),
        ('Region V', 'V', 'Bicol Region'),
        ('Region VI', 'VI', 'Western Visayas'),
        ('Negros Island Region', 'NIR', 'Negros Island Region'),
        ('Region VII', 'VII', 'Central Visayas'),
        ('Region VIII', 'VIII', 'Eastern Visayas'),
        ('Region IX', 'IX', 'Zamboanga Peninsula'),
        ('Region X', 'X', 'Northern Mindanao'),
        ('Region XI', 'XI', 'Davao Region'),
        ('Region XII', 'XII', 'SOCCSKSARGEN'),
        ('Region XIII', 'XIII', 'Caraga'),
        ('Bangsamoro Autonomous Region in Muslim Mindanao', 'BARMM', 'Bangsamoro Autonomous Region in Muslim Mindanao')
    AS r(source_region, region_code, standard_region_name)
)
SELECT
    p.region AS region_as_stored,
    p.region_name AS region_name_as_stored,
    r.region_code,
    r.standard_region_name,
    CASE WHEN r.region_code IS NULL THEN 'UNMAPPED' ELSE 'MAPPED' END AS status,
    COUNT(*) AS row_count
FROM poverty_incidence_profile p
LEFT JOIN region_ref r
    ON p.region = r.source_region
GROUP BY p.region, p.region_name, r.region_code, r.standard_region_name
ORDER BY status DESC, r.region_code;

-- 5.4 Districts, cities and areas affected by boundary changes
SELECT
    geographic_level,
    region,
    province,
    CONCAT_WS(', ', ARRAY_SORT(COLLECT_SET(CAST(year AS STRING)))) AS years
FROM poverty_incidence_profile
WHERE geographic_level IN ('district', 'city')
   OR province LIKE 'Maguindanao%'
   OR province IN ('Sulu', 'Cotabato')
GROUP BY geographic_level, region, province
ORDER BY geographic_level, region, province;

-- 5.5 Units agree with sheets (tab1 = families, tab2 = population)
SELECT
    source_page,
    measure,
    COUNT(*) AS row_count,
    CASE
        WHEN (source_page = 'tab1' AND measure = 'families')
          OR (source_page = 'tab2' AND measure = 'population') THEN 'MATCH'
        ELSE 'ISSUE'
    END AS status
FROM poverty_incidence_profile
GROUP BY source_page, measure
ORDER BY source_page;

-- 5.6 Same area and year: threshold equal in both sheets, family rate not above population rate
WITH by_area AS (
    SELECT
        year,
        region,
        province,
        MAX(CASE WHEN measure = 'families' THEN threshold_php END) AS threshold_families,
        MAX(CASE WHEN measure = 'population' THEN threshold_php END) AS threshold_population,
        MAX(CASE WHEN measure = 'families' THEN estimate_pct END) AS rate_families,
        MAX(CASE WHEN measure = 'population' THEN estimate_pct END) AS rate_population
    FROM poverty_incidence_profile
    GROUP BY year, region, province
)
SELECT
    COUNT(*) AS area_years,
    COUNT_IF(threshold_families <> threshold_population) AS threshold_differs,
    COUNT_IF(rate_families > rate_population) AS family_rate_above_population_rate,
    COUNT_IF(threshold_families IS NULL OR threshold_population IS NULL) AS missing_from_one_sheet
FROM by_area;


-- 6. ACCURACY AND RECONCILIATION

-- 6.1 National rate vs regional rates. Rates cannot be summed, but a national
-- average must fall between the lowest and highest regional rate.
WITH reconciliation AS (
    SELECT
        year,
        measure,
        MAX(CASE WHEN geographic_level = 'national' THEN estimate_pct END) AS national_rate,
        MIN(CASE WHEN geographic_level = 'region' THEN estimate_pct END) AS lowest_regional_rate,
        MAX(CASE WHEN geographic_level = 'region' THEN estimate_pct END) AS highest_regional_rate
    FROM poverty_incidence_profile
    GROUP BY year, measure
)
SELECT
    *,
    CASE
        WHEN national_rate BETWEEN lowest_regional_rate AND highest_regional_rate THEN 'MATCH'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY year, measure;

-- 6.2 Each regional rate vs its own provinces, districts and cities
WITH reconciliation AS (
    SELECT
        year,
        measure,
        region,
        MAX(CASE WHEN geographic_level = 'region' THEN estimate_pct END) AS regional_rate,
        MIN(CASE WHEN geographic_level NOT IN ('national', 'region') THEN estimate_pct END) AS lowest_area_rate,
        MAX(CASE WHEN geographic_level NOT IN ('national', 'region') THEN estimate_pct END) AS highest_area_rate
    FROM poverty_incidence_profile
    WHERE geographic_level <> 'national'
    GROUP BY year, measure, region
)
SELECT
    *,
    CASE
        WHEN regional_rate BETWEEN lowest_area_rate AND highest_area_rate THEN 'MATCH'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY status, year, measure, region;

-- 6.3 Regional vs national poverty incidence among families
WITH national AS (
    SELECT year, estimate_pct AS national_rate
    FROM poverty_incidence_profile
    WHERE geographic_level = 'national' AND measure = 'families'
)
SELECT
    p.year,
    p.region,
    p.estimate_pct AS regional_rate,
    n.national_rate,
    p.estimate_pct - n.national_rate AS difference_pp
FROM poverty_incidence_profile p
JOIN national n
    ON p.year = n.year
WHERE p.geographic_level = 'region'
  AND p.measure = 'families'
ORDER BY p.year, regional_rate DESC;

-- 6.4 Trace back to the source file: compare these 10 values with the Excel cells
SELECT
    source_page,
    source_row AS excel_row,
    year,
    region,
    province,
    threshold_php,
    estimate_pct,
    coeff_var
FROM poverty_incidence_profile
ORDER BY RAND(42)
LIMIT 10;


-- 7. SILVER TREATMENT

-- 7.1 Silver preview: standard region codes, geographic level, numbers and note flags
CREATE OR REPLACE TEMP VIEW poverty_incidence_silver_preview AS
WITH region_ref AS (
    SELECT * FROM VALUES
        ('PHILIPPINES', 'PHL', 'Philippines'),
        ('National Capital Region', 'NCR', 'National Capital Region'),
        ('Cordillera Administrative Region', 'CAR', 'Cordillera Administrative Region'),
        ('Region I', 'I', 'Ilocos Region'),
        ('Region II', 'II', 'Cagayan Valley'),
        ('Region III', 'III', 'Central Luzon'),
        ('Region IV-A', 'IVA', 'CALABARZON'),
        ('MIMAROPA Region', 'IVB', 'MIMAROPA Region'),
        ('Region V', 'V', 'Bicol Region'),
        ('Region VI', 'VI', 'Western Visayas'),
        ('Negros Island Region', 'NIR', 'Negros Island Region'),
        ('Region VII', 'VII', 'Central Visayas'),
        ('Region VIII', 'VIII', 'Eastern Visayas'),
        ('Region IX', 'IX', 'Zamboanga Peninsula'),
        ('Region X', 'X', 'Northern Mindanao'),
        ('Region XI', 'XI', 'Davao Region'),
        ('Region XII', 'XII', 'SOCCSKSARGEN'),
        ('Region XIII', 'XIII', 'Caraga'),
        ('Bangsamoro Autonomous Region in Muslim Mindanao', 'BARMM', 'Bangsamoro Autonomous Region in Muslim Mindanao')
    AS r(source_region, region_code, standard_region_name)
)
SELECT
    p.year,
    p.measure,
    p.geographic_level,
    r.region_code,
    r.standard_region_name AS region_name,
    CASE WHEN p.province = '' THEN r.standard_region_name ELSE p.province END AS area_name,
    p.threshold_php AS poverty_threshold_php,
    p.estimate_pct AS poverty_incidence_pct,
    p.coeff_var AS coefficient_of_variation,
    p.standard_error,
    p.ci_lower AS ci_lower_pct,
    p.ci_upper AS ci_upper_pct,
    ARRAY_CONTAINS(p.note_codes, '1/') AS sig_change_2021_2023,
    ARRAY_CONTAINS(p.note_codes, '2/') AS sig_change_2023_2025,
    ARRAY_CONTAINS(p.note_codes, 'b/') AS use_with_caution,
    ARRAY_CONTAINS(p.note_codes, 'c/') AS below_0_05_pct,
    ARRAY_CONTAINS(p.note_codes, 'r1/') AS revised_sulu_transfer,
    ARRAY_CONTAINS(p.note_codes, 'r2/') AS revised_north_cotabato_transfer,
    (p.province = 'Maguindanao' AND p.year >= 2023) AS is_combined_area,
    p.source_page,
    p.source_row
FROM poverty_incidence_profile p
LEFT JOIN region_ref r
    ON p.region = r.source_region;

-- 7.2 Silver readiness. Expected: 644 rows, 0 duplicates, 0 unmapped, 0 missing estimates.
SELECT
    COUNT(*) AS silver_rows,
    COUNT(*) - COUNT(DISTINCT year, measure, region_code, area_name) AS duplicate_business_keys,
    COUNT_IF(region_code IS NULL) AS unmapped_regions,
    COUNT_IF(poverty_incidence_pct IS NULL) AS missing_estimates,
    COUNT_IF(use_with_caution) AS use_with_caution_rows,
    COUNT_IF(is_combined_area) AS combined_area_rows
FROM poverty_incidence_silver_preview;

-- 7.3 Silver preview: national and regional rows, families
SELECT *
FROM poverty_incidence_silver_preview
WHERE geographic_level IN ('national', 'region')
  AND measure = 'families'
ORDER BY year, region_code;


-- 8. OPTIONAL: INGESTION LINEAGE
-- Run only if the Bronze table has the pipeline columns (_source_file, _run_id, ...).
-- If DESCRIBE in 1.1 does not show them, skip this query.
SELECT
    _source_file,
    _run_id,
    COUNT(*) AS row_count,
    COUNT_IF(_rescued_data IS NOT NULL) AS rescued_rows,
    COUNT_IF(
        NULLIF(TRIM(_drive_file_id), '') IS NULL
        OR NULLIF(TRIM(_landing_file), '') IS NULL
        OR NULLIF(TRIM(_content_hash), '') IS NULL
        OR NULLIF(TRIM(_dataset_hash), '') IS NULL
        OR NULLIF(TRIM(_run_id), '') IS NULL
        OR _ingested_at IS NULL
    ) AS incomplete_lineage_rows,
    MIN(_ingested_at) AS earliest_ingestion,
    MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.poverty_incidence
GROUP BY _source_file, _run_id;
