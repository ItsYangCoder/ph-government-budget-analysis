-- Dataset: regional_obligation
-- Table: pondolens.dev_bronze.regional_obligations
-- Owner: Mia Barroga
-- Scope: active
-- Execute the complete file in one Databricks SQL session.
-- Persistent tables are read-only; session TEMP VIEWs are allowed.
-- Evidence and unresolved checks: findings.md. Column definitions: data_dictionary.md.

DESCRIBE TABLE pondolens.dev_bronze.regional_obligations;

CREATE OR REPLACE TEMP VIEW regional_obligations_profile AS
WITH raw AS (
 SELECT *, TRIM(year) AS year_text, TRIM(expenditure_amount) AS amount_raw,
  NULLIF(UPPER(TRIM(category)), '') AS category_key,
  NULLIF(UPPER(TRIM(particulars)), '') AS particular_key,
  NULLIF(REGEXP_REPLACE(UPPER(TRIM(regions)), '[^A-Z0-9]', ''), '') AS region_key
 FROM pondolens.dev_bronze.regional_obligations
), parsed AS (
 SELECT *, TRY_CAST(year_text AS INT) AS parsed_year,
 TRY_CAST(CASE WHEN amount_raw RLIKE '^\\(.*\\)$'
  THEN CONCAT('-', REPLACE(SUBSTRING(amount_raw, 2, LENGTH(amount_raw)-2), ',', ''))
  ELSE REPLACE(amount_raw, ',', '') END AS DECIMAL(30,10)) AS numeric_amount
 FROM raw
)
SELECT *, CASE WHEN amount_raw IS NULL OR amount_raw='' THEN 'missing'
 WHEN amount_raw IN ('-','–','—') THEN 'source_marker'
 WHEN numeric_amount IS NULL THEN 'invalid' ELSE 'numeric' END AS amount_status,
 CASE WHEN category_key='GRAND TOTAL' THEN 'grand_total'
 WHEN particular_key='ALL' THEN 'category_subtotal' ELSE 'detail' END AS row_type,
 CASE WHEN region_key='TOTAL' THEN 'total' WHEN region_key='NATIONWIDE' THEN 'nationwide'
 WHEN region_key='CENTRALOFFICE' THEN 'central_office' ELSE 'region' END AS location_type
FROM parsed;

SELECT COUNT(*) AS total_rows, COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(year_text IS NULL OR NOT(year_text RLIKE '^[0-9]{4}$') OR parsed_year IS NULL) AS invalid_years,
 COUNT_IF(parsed_year NOT BETWEEN 2021 AND 2025) AS outside_project_years,
 COUNT_IF(category_key IS NULL OR particular_key IS NULL OR region_key IS NULL) AS incomplete_keys,
 COUNT_IF(NULLIF(TRIM(_rescued_data),'') IS NOT NULL) AS rescued_rows
FROM regional_obligations_profile;

SELECT parsed_year, price_basis, unit_amount, row_type, location_type, amount_status,
 COUNT(*) AS row_count, MIN(numeric_amount) AS minimum_amount, MAX(numeric_amount) AS maximum_amount,
 COUNT_IF(numeric_amount < 0) AS negative_amounts
FROM regional_obligations_profile
GROUP BY parsed_year, price_basis, unit_amount, row_type, location_type, amount_status
ORDER BY parsed_year, row_type, location_type, amount_status;

-- Source-aware candidate key. Retain duplicates for review, never silently DISTINCT them away.
SELECT parsed_year, category_key, particular_key, region_key, price_basis, unit_amount,
 COUNT(*) AS occurrences, COLLECT_SET(_source_file) AS source_files
FROM regional_obligations_profile
GROUP BY parsed_year, category_key, particular_key, region_key, price_basis, unit_amount
HAVING COUNT(*) > 1;

SELECT _source_file, parsed_year, amount_raw, amount_status, category, particulars, regions, source_page
FROM regional_obligations_profile WHERE amount_status <> 'numeric'
ORDER BY parsed_year, _source_file, category, particulars, regions;

CREATE OR REPLACE TEMP VIEW regional_obligations_profile_aliases AS
SELECT DISTINCT REGEXP_REPLACE(UPPER(TRIM(source_region)), '[^A-Z0-9]', '') AS alias_key,
 region_code, region_name, valid_from_year, valid_to_year
FROM pondolens.dev_silver.shared_region_crosswalk
UNION
SELECT DISTINCT REGEXP_REPLACE(UPPER(TRIM(region_name)), '[^A-Z0-9]', ''),
 region_code, region_name, valid_from_year, valid_to_year
FROM pondolens.dev_silver.shared_region_crosswalk
UNION
SELECT DISTINCT REGEXP_REPLACE(UPPER(TRIM(region_code)), '[^A-Z0-9]', ''),
 region_code, region_name, valid_from_year, valid_to_year
FROM pondolens.dev_silver.shared_region_crosswalk;

-- TOTAL is an aggregate label and does not require a region code.
-- Zero or multiple mappings require review; do not edit shared crosswalk years here.
SELECT p.parsed_year, p.regions AS source_region, p.location_type,
 COLLECT_SET(NAMED_STRUCT('region_code', x.region_code, 'region_name', x.region_name)) AS mappings,
 COUNT(DISTINCT CASE WHEN x.region_code IS NOT NULL
 THEN NAMED_STRUCT('region_code', x.region_code, 'region_name', x.region_name) END) AS mapping_count
FROM (SELECT DISTINCT parsed_year, regions, region_key, location_type FROM regional_obligations_profile) p
LEFT JOIN regional_obligations_profile_aliases x ON p.region_key=x.alias_key
 AND p.parsed_year BETWEEN x.valid_from_year AND x.valid_to_year
WHERE p.location_type <> 'total'
GROUP BY p.parsed_year, p.regions, p.location_type ORDER BY p.parsed_year, p.regions;

-- Reconcile only numeric, unique groups. Dash meaning is not assumed.
-- Publish component coverage and unresolved counts; a partial SUM is not a passing total.
WITH groups AS (
 SELECT parsed_year, _source_file, category_key, particular_key, price_basis, unit_amount,
 COUNT_IF(location_type='total') AS reported_total_rows,
 COUNT_IF(location_type<>'total') AS component_rows,
 COUNT(*)-COUNT(DISTINCT region_key) AS duplicate_locations,
 COUNT_IF(amount_status<>'numeric') AS unresolved_rows,
 MAX(CASE WHEN location_type='total' THEN numeric_amount END) AS reported_total,
 SUM(CASE WHEN location_type<>'total' THEN numeric_amount END) AS component_sum
 FROM regional_obligations_profile
 GROUP BY parsed_year, _source_file, category_key, particular_key, price_basis, unit_amount
)
SELECT *, CASE WHEN reported_total_rows<>1 OR component_rows=0 OR duplicate_locations>0 OR unresolved_rows>0
 THEN 'REVIEW_STRUCTURE_OR_MARKERS'
 WHEN reported_total=component_sum THEN 'MATCH' ELSE 'DIFFERENCE' END AS check_status,
 CASE WHEN reported_total_rows=1 AND component_rows>0 AND duplicate_locations=0 AND unresolved_rows=0
 THEN reported_total-component_sum END AS difference
FROM groups ORDER BY parsed_year, _source_file, category_key, particular_key;

-- Category moves affect cross-year entity matching.
SELECT particular_key, COLLECT_SET(category_key) AS categories, COLLECT_SET(parsed_year) AS years
FROM regional_obligations_profile WHERE row_type='detail'
GROUP BY particular_key HAVING COUNT(DISTINCT category_key)>1;

SELECT _source_file, _run_id, COUNT(*) AS row_count,
 COUNT_IF(NULLIF(TRIM(_drive_file_id),'') IS NULL OR NULLIF(TRIM(_source_file),'') IS NULL
 OR NULLIF(TRIM(_landing_file),'') IS NULL OR NULLIF(TRIM(_content_hash),'') IS NULL
 OR NULLIF(TRIM(_dataset_hash),'') IS NULL OR NULLIF(TRIM(_run_id),'') IS NULL
 OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM regional_obligations_profile GROUP BY _source_file, _run_id;

-- Category reconciliation: each category subtotal is compared with its detail records.
WITH totals AS (
 SELECT parsed_year, _source_file, region_key, category_key, price_basis, unit_amount,
 COUNT_IF(row_type='category_subtotal') AS reported_total_rows,
 COUNT_IF(row_type='detail') AS component_rows,
 COUNT(*)-COUNT(DISTINCT particular_key) AS duplicate_particulars,
 COUNT_IF(amount_status<>'numeric') AS unresolved_rows,
 MAX(CASE WHEN row_type='category_subtotal' THEN numeric_amount END) AS reported_total,
 SUM(CASE WHEN row_type='detail' THEN numeric_amount END) AS component_sum
 FROM regional_obligations_profile WHERE row_type<>'grand_total'
 GROUP BY parsed_year, _source_file, region_key, category_key, price_basis, unit_amount
)
SELECT *, CASE WHEN reported_total_rows<>1 OR component_rows=0 OR duplicate_particulars>0 OR unresolved_rows>0
 THEN 'REVIEW_STRUCTURE_OR_MARKERS' WHEN reported_total=component_sum THEN 'MATCH'
 ELSE 'DIFFERENCE' END AS check_status,
 CASE WHEN reported_total_rows=1 AND component_rows>0 AND duplicate_particulars=0 AND unresolved_rows=0
 THEN reported_total-component_sum END AS difference
FROM totals ORDER BY parsed_year, _source_file, region_key, category_key;

-- Grand total reconciliation uses category subtotals only, never detail plus subtotals.
WITH totals AS (
 SELECT parsed_year, _source_file, region_key, price_basis, unit_amount,
 COUNT_IF(row_type='grand_total') AS reported_total_rows,
 COUNT_IF(row_type='category_subtotal') AS component_rows,
 COUNT(*)-COUNT(DISTINCT category_key) AS duplicate_categories,
 COUNT_IF(amount_status<>'numeric') AS unresolved_rows,
 MAX(CASE WHEN row_type='grand_total' THEN numeric_amount END) AS reported_total,
 SUM(CASE WHEN row_type='category_subtotal' THEN numeric_amount END) AS component_sum
 FROM regional_obligations_profile WHERE row_type<>'detail'
 GROUP BY parsed_year, _source_file, region_key, price_basis, unit_amount
)
SELECT *, CASE WHEN reported_total_rows<>1 OR component_rows=0 OR duplicate_categories>0 OR unresolved_rows>0
 THEN 'REVIEW_STRUCTURE_OR_MARKERS' WHEN reported_total=component_sum THEN 'MATCH'
 ELSE 'DIFFERENCE' END AS check_status,
 CASE WHEN reported_total_rows=1 AND component_rows>0 AND duplicate_categories=0 AND unresolved_rows=0
 THEN reported_total-component_sum END AS difference
FROM totals ORDER BY parsed_year, _source_file, region_key;
