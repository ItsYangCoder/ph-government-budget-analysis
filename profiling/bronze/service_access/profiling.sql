-- Service access — Bronze profiling
-- Prepared for Joy / PondoLens, 20 October 2026.
-- Run in one Databricks SQL session. Only TEMP VIEWs are created.
-- TABLE PATH: pondolens.dev_bronze.service_access.
-- Confirm this path before execution; the attachment does not identify its table.
-- Results in findings.md were computed from the supplied export, not this live table.

-- 1. Structure and lineage.
DESCRIBE TABLE pondolens.dev_bronze.service_access;
SELECT column_name, full_data_type
FROM pondolens.information_schema.columns
WHERE table_schema = 'dev_bronze' AND table_name = 'service_access'
ORDER BY ordinal_position;

CREATE OR REPLACE TEMP VIEW service_access_profile AS
SELECT *,
  UPPER(REGEXP_REPLACE(TRIM(region), r'\s+', ' ')) AS region_key,
  TRIM(indicator) AS indicator_key,
  TRIM(source) AS source_key,
  TRIM(unit) AS unit_key,
  TRIM(breakdown_type) AS breakdown_type_key,
  TRIM(breakdown_value) AS breakdown_value_key,
  TRY_CAST(TRIM(CAST(year AS STRING)) AS DECIMAL(38,10)) AS year_num,
  TRY_CAST(TRIM(CAST(value AS STRING)) AS DECIMAL(38,15)) AS value_num,
  CASE WHEN value IS NULL OR LOWER(TRIM(CAST(value AS STRING))) IN ('','null')
    THEN TRUE ELSE FALSE END AS value_missing,
  CASE WHEN UPPER(TRIM(region)) IN ('NATIONAL','PHILIPPINES') THEN 'national'
       WHEN region IS NULL OR LOWER(TRIM(region)) IN ('','null') THEN 'unknown'
       ELSE 'regional' END AS geographic_level
FROM pondolens.dev_bronze.service_access;

-- Definitions are source-specific. Do not select solely by indicator text.
CREATE OR REPLACE TEMP VIEW service_access_scope AS
SELECT * FROM service_access_profile
WHERE year_num IN (2022,2024)
  AND source_key = 'PSA APIS'
  AND indicator_key IN (
    'At least basic drinking-water access',
    'Basic sanitation access', 'Basic handwashing facilities');

SELECT COUNT(*) AS total_rows, MIN(year_num) AS min_year, MAX(year_num) AS max_year,
 COUNT(DISTINCT indicator_key) AS indicators, COUNT(DISTINCT region_key) AS areas,
 COUNT(DISTINCT source_key) AS sources FROM service_access_profile;
SELECT source, _source_file, _source_sheet, COUNT(*) AS rows,
 COUNT(DISTINCT _run_id) AS ingestion_runs, MIN(_ingested_at) AS first_ingestion,
 MAX(_ingested_at) AS last_ingestion
FROM service_access_profile GROUP BY source, _source_file, _source_sheet;

-- 2. Completeness, including ingestion columns. Source-sheet NULL is expected for CSV.
CREATE OR REPLACE TEMP VIEW service_access_fields AS
SELECT field, raw_value FROM pondolens.dev_bronze.service_access
LATERAL VIEW STACK(
22,
  'country', CAST(`country` AS STRING),
  'region', CAST(`region` AS STRING),
  'year', CAST(`year` AS STRING),
  'indicator', CAST(`indicator` AS STRING),
  'breakdown_type', CAST(`breakdown_type` AS STRING),
  'breakdown_value', CAST(`breakdown_value` AS STRING),
  'value', CAST(`value` AS STRING),
  'unit', CAST(`unit` AS STRING),
  'source', CAST(`source` AS STRING),
  'source_url', CAST(`source_url` AS STRING),
  'notes', CAST(`notes` AS STRING),
  '_rescued_data', CAST(`_rescued_data` AS STRING),
  '_drive_file_id', CAST(`_drive_file_id` AS STRING),
  '_source_file', CAST(`_source_file` AS STRING),
  '_landing_file', CAST(`_landing_file` AS STRING),
  '_source_modified_at', CAST(`_source_modified_at` AS STRING),
  '_source_sheet', CAST(`_source_sheet` AS STRING),
  '_content_hash', CAST(`_content_hash` AS STRING),
  '_header_map', CAST(`_header_map` AS STRING),
  '_dataset_hash', CAST(`_dataset_hash` AS STRING),
  '_run_id', CAST(`_run_id` AS STRING),
  '_ingested_at', CAST(`_ingested_at` AS STRING)
) s AS field, raw_value;
SELECT field, COUNT(*) AS rows,
 COUNT_IF(raw_value IS NULL OR LOWER(TRIM(raw_value)) IN ('','null')) AS missing_values
FROM service_access_fields GROUP BY field ORDER BY field;
SELECT year_num, source_key, indicator_key, geographic_level,
 COUNT(*) AS rows, COUNT_IF(value_missing) AS missing_values,
 COUNT(DISTINCT region_key) AS areas
FROM service_access_profile
GROUP BY year_num,source_key,indicator_key,geographic_level
ORDER BY indicator_key,source_key,year_num,geographic_level;

-- Independent project checklist: 17 source regions; no fabricated NIR observation.
CREATE OR REPLACE TEMP VIEW service_access_expected_regions AS
SELECT * FROM VALUES
 ('BARMM'),
 ('CAR'),
 ('MIMAROPA'),
 ('NCR'),
 ('REGION I (ILOCOS REGION)'),
 ('REGION II (CAGAYAN VALLEY)'),
 ('REGION III (CENTRAL LUZON)'),
 ('REGION IV-A (CALABARZON)'),
 ('REGION IX (ZAMBOANGA PENINSULA)'),
 ('REGION V (BICOL REGION)'),
 ('REGION VI (WESTERN VISAYAS)'),
 ('REGION VII (CENTRAL VISAYAS)'),
 ('REGION VIII (EASTERN VISAYAS)'),
 ('REGION X (NORTHERN MINDANAO)'),
 ('REGION XI (DAVAO REGION)'),
 ('REGION XII (SOCCSKSARGEN)'),
 ('REGION XIII (CARAGA)') AS t(region_key);
WITH expected AS (
 SELECT r.region_key, y.year_num, i.indicator_key
 FROM service_access_expected_regions r
 CROSS JOIN (SELECT * FROM VALUES (2022),(2024) AS t(year_num)) y
 CROSS JOIN (SELECT * FROM VALUES
 ('At least basic drinking-water access'),('Basic sanitation access'),
 ('Basic handwashing facilities') AS t(indicator_key)) i
)
SELECT e.*,COUNT(s.region_key) AS actual_rows,
 COUNT_IF(s.value_num IS NOT NULL) AS populated_values
FROM expected e LEFT JOIN service_access_scope s
 ON e.region_key=s.region_key AND e.year_num=s.year_num AND e.indicator_key=s.indicator_key
GROUP BY e.region_key,e.year_num,e.indicator_key
HAVING COUNT(s.region_key)<>1 OR COUNT_IF(s.value_num IS NOT NULL)<>1;
-- Unexpected regional labels, including unsupported future NIR records.
SELECT s.region_key,COUNT(*) AS rows FROM service_access_scope s
LEFT ANTI JOIN service_access_expected_regions e ON s.region_key=e.region_key
WHERE s.geographic_level='regional' GROUP BY s.region_key;

-- 3. Exact duplicates and repeated business keys.
WITH serialized AS (
 SELECT 'all columns' AS check_name,TO_JSON(STRUCT(*)) AS record
 FROM pondolens.dev_bronze.service_access
 UNION ALL
 SELECT 'business columns',TO_JSON(STRUCT(country,region,year,indicator,
 breakdown_type,breakdown_value,value,unit,source,source_url,notes))
 FROM pondolens.dev_bronze.service_access
), grouped AS (SELECT check_name,record,COUNT(*) n FROM serialized GROUP BY check_name,record)
SELECT check_name,SUM(n) AS rows,COUNT_IF(n>1) AS duplicate_groups,
 SUM(CASE WHEN n>1 THEN n-1 ELSE 0 END) AS excess_rows FROM grouped GROUP BY check_name;
SELECT country,region_key,year_num,indicator_key,breakdown_type_key,
 breakdown_value_key,unit_key,source_key,COUNT(*) AS rows,
 COUNT(DISTINCT value_num) AS distinct_nonnull_values,
 COUNT_IF(value_missing) AS missing_values
FROM service_access_profile
GROUP BY country,region_key,year_num,indicator_key,breakdown_type_key,
 breakdown_value_key,unit_key,source_key HAVING COUNT(*)>1;
-- Candidate Gold grain before canonical crosswalk mapping.
SELECT region_key,year_num,indicator_key,COUNT(*) AS rows
FROM service_access_scope GROUP BY region_key,year_num,indicator_key HAVING COUNT(*)>1;

-- 4. Validity: percentage measurements, not unemployment rates or counts.
SELECT COUNT(*) AS rows,
 COUNT_IF(year_num IS NULL OR year_num<>FLOOR(year_num) OR year_num NOT BETWEEN 2021 AND 2025) AS invalid_years,
 COUNT_IF(value_missing) AS missing_values,
 COUNT_IF(NOT value_missing AND value_num IS NULL) AS malformed_values,
 COUNT_IF(value_num<0 OR value_num>100) AS outside_0_100,
 COUNT_IF(value_num=0) AS zero_values,
 COUNT_IF(_rescued_data IS NOT NULL AND LOWER(TRIM(CAST(_rescued_data AS STRING))) NOT IN ('','null')) AS rescued_rows,
 COUNT_IF(LOWER(TRIM(country))<>'philippines' OR country IS NULL) AS unexpected_country
FROM service_access_profile;
SELECT indicator_key,year_num,source_key,unit_key,geographic_level,
 COUNT(*) AS rows,COUNT(value_num) AS populated_values,
 MIN(value_num) AS minimum,MAX(value_num) AS maximum,AVG(value_num) AS descriptive_mean
FROM service_access_profile
GROUP BY indicator_key,year_num,source_key,unit_key,geographic_level
ORDER BY indicator_key,source_key,year_num,geographic_level;
-- Means describe rows only; they are not national survey estimates.

-- 5. Consistency and categorical inventories.
SELECT region,region_key,geographic_level,COUNT(*) AS rows
FROM service_access_profile GROUP BY region,region_key,geographic_level;
SELECT indicator_key,source_key,unit_key,breakdown_type_key,breakdown_value_key,
 COUNT(*) AS rows FROM service_access_profile
GROUP BY indicator_key,source_key,unit_key,breakdown_type_key,breakdown_value_key;
SELECT indicator_key,COUNT(*) AS rows,
 COUNT_IF(breakdown_type_key<>'Total' OR breakdown_type_key IS NULL) AS unexpected_breakdown,
 COUNT_IF(CASE WHEN indicator_key='Basic handwashing facilities'
 THEN unit_key<>'% of consenting families' OR breakdown_value_key<>'Consenting families'
 ELSE unit_key<>'% of families' OR breakdown_value_key<>'All families' END
 OR unit_key IS NULL OR breakdown_value_key IS NULL) AS definition_mismatches
FROM service_access_scope GROUP BY indicator_key;
-- Status is embedded in notes; this is a diagnostic, not an authoritative status parser.
SELECT year_num,CASE
 WHEN LOWER(notes) LIKE '%preliminary survey results%' THEN 'preliminary'
 WHEN LOWER(notes) LIKE '%final survey results%' THEN 'final'
 WHEN LOWER(notes) LIKE 'missing:%' THEN 'missing'
 ELSE 'other_or_unclassified' END AS note_status, COUNT(*) AS rows
FROM service_access_scope GROUP BY ALL;
SELECT source_key,indicator_key,notes,COUNT(*) AS rows
FROM service_access_profile GROUP BY source_key,indicator_key,notes;

-- 6. Accuracy/reconciliation: national rates must NOT be summed from regions.
-- Unweighted regional means below are diagnostic and not expected to equal national rates.
SELECT year_num,indicator_key,unit_key,
 COUNT_IF(geographic_level='regional') AS regional_rows,
 COUNT_IF(geographic_level='national') AS national_rows,
 MIN(CASE WHEN geographic_level='national' THEN value_num END) AS national_min,
 MAX(CASE WHEN geographic_level='national' THEN value_num END) AS national_max,
 MIN(CASE WHEN geographic_level='regional' THEN value_num END) AS regional_min,
 MAX(CASE WHEN geographic_level='regional' THEN value_num END) AS regional_max,
 AVG(CASE WHEN geographic_level='regional' THEN value_num END) AS unweighted_regional_mean
FROM service_access_scope GROUP BY year_num,indicator_key,unit_key ORDER BY indicator_key,year_num;
-- Source-file accuracy remains NOT RUN: requires original workbook and cell mapping.
-- No numerator/denominator counts or survey weights are available for weighted reconciliation.

-- 7. Silver readiness summary. Not an automatic authorization to load.
SELECT COUNT(*) AS apis_scope_rows,
 COUNT_IF(geographic_level='regional') AS regional_rows,
 COUNT_IF(geographic_level='national') AS national_rows,
 COUNT_IF(value_missing OR value_num IS NULL OR value_num<0 OR value_num>100) AS invalid_or_missing_values
FROM service_access_scope;
-- Before Silver: use confirmed shared crosswalk schema to validate one match per
-- source label + year, no join fan-out, no unmapped keys, and no duplicate canonical keys.
-- Crosswalk SQL deliberately deferred: its current schema was not supplied here.
-- Preserve original geography, Sulu notes, source/release status and lineage.
-- Do not impute missing years, fill missing percentages with zero, or invent NIR.
