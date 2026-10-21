-- Dataset: hospital
-- Table: pondolens.dev_bronze.hospital
-- Owner: Joy
-- Scope: active
-- Execute the complete file in one Databricks SQL session.
-- Persistent tables are read-only; session TEMP VIEWs are allowed.
-- Evidence and unresolved checks: findings.md. Column definitions: data_dictionary.md.

DESCRIBE TABLE pondolens.dev_bronze.hospital;

CREATE OR REPLACE TEMP VIEW hospital_profile AS
SELECT *, TRIM(year) AS raw_year,
 TRY_CAST(TRIM(year) AS INT) AS parsed_year,
 TRIM(regulated_hospital_count) AS raw_count,
 TRY_CAST(TRIM(regulated_hospital_count) AS INT) AS parsed_count,
 UPPER(TRIM(hospital_type)) AS type_key,
 REGEXP_REPLACE(UPPER(TRIM(region_name)), '[^A-Z0-9]', '') AS region_key
FROM pondolens.dev_bronze.hospital;

-- No source filtering: malformed and out-of-scope rows remain visible.
SELECT COUNT(*) AS total_rows,
 COUNT_IF(raw_year IS NULL OR NOT (raw_year RLIKE '^[0-9]{4}$')
   OR parsed_year IS NULL) AS invalid_years,
 COUNT_IF(parsed_year NOT BETWEEN 2021 AND 2024) AS outside_snapshot_years,
 COUNT_IF(NULLIF(TRIM(region_name), '') IS NULL) AS missing_regions,
 COUNT_IF(raw_count IS NULL OR NOT (raw_count RLIKE '^[0-9]+$')
   OR parsed_count IS NULL) AS invalid_counts,
 COUNT_IF(parsed_count < 0) AS negative_counts,
 COUNT_IF(type_key IS NULL OR type_key NOT IN ('GOVERNMENT','PRIVATE','TOTAL')) AS invalid_types,
 COUNT_IF(unit IS NULL OR LOWER(TRIM(unit)) <> 'hospitals') AS invalid_units
FROM hospital_profile;

SELECT parsed_year, type_key, unit, COUNT(*) AS row_count,
 COUNT(DISTINCT region_key) AS locations, MIN(parsed_count) AS minimum_count,
 MAX(parsed_count) AS maximum_count
FROM hospital_profile GROUP BY parsed_year, type_key, unit
ORDER BY parsed_year, type_key, unit;

SELECT parsed_year, region_key, type_key, COUNT(*) AS occurrences
FROM hospital_profile GROUP BY parsed_year, region_key, type_key
HAVING COUNT(*) > 1;

-- Distinct aliases avoid multiplying identical crosswalk mappings.
CREATE OR REPLACE TEMP VIEW hospital_profile_aliases AS
SELECT DISTINCT alias_key, region_code, region_name, valid_from_year, valid_to_year
FROM (
 SELECT REGEXP_REPLACE(UPPER(TRIM(source_region)), '[^A-Z0-9]', '') AS alias_key,
  region_code, region_name, valid_from_year, valid_to_year
 FROM pondolens.dev_silver.shared_region_crosswalk
 UNION ALL
 SELECT REGEXP_REPLACE(UPPER(TRIM(region_name)), '[^A-Z0-9]', ''),
  region_code, region_name, valid_from_year, valid_to_year
 FROM pondolens.dev_silver.shared_region_crosswalk
 UNION ALL
 -- Source-specific prefix; canonical code/name still come from the crosswalk.
 SELECT 'NCRNATIONALCAPITALREGION', region_code, region_name, valid_from_year, valid_to_year
 FROM pondolens.dev_silver.shared_region_crosswalk WHERE region_code = 'NCR'
);

SELECT h.parsed_year, h.region_name AS source_region_name,
 COLLECT_SET(NAMED_STRUCT('region_code', x.region_code, 'region_name', x.region_name)) AS mappings,
 COUNT(DISTINCT CASE WHEN x.region_code IS NOT NULL
  THEN NAMED_STRUCT('region_code', x.region_code, 'region_name', x.region_name) END) AS mapping_count
FROM (SELECT DISTINCT parsed_year, region_name, region_key FROM hospital_profile) h
LEFT JOIN hospital_profile_aliases x ON h.region_key = x.alias_key
 AND h.parsed_year BETWEEN x.valid_from_year AND x.valid_to_year
GROUP BY h.parsed_year, h.region_name ORDER BY h.parsed_year, h.region_name;

-- The current snapshot contains Government only. Missing categories are not zero.
-- Only assess totals when each of the three categories exists exactly once and parses.
WITH counts AS (
 SELECT parsed_year, region_key,
 COUNT_IF(type_key='TOTAL') AS total_rows,
 COUNT_IF(type_key='GOVERNMENT') AS government_rows,
 COUNT_IF(type_key='PRIVATE') AS private_rows,
 COUNT_IF(parsed_count IS NULL OR raw_count IS NULL OR NOT(raw_count RLIKE '^[0-9]+$')) AS invalid_rows,
 MAX(CASE WHEN type_key='TOTAL' THEN parsed_count END) AS total_count,
 MAX(CASE WHEN type_key='GOVERNMENT' THEN parsed_count END) AS government_count,
 MAX(CASE WHEN type_key='PRIVATE' THEN parsed_count END) AS private_count
 FROM hospital_profile GROUP BY parsed_year, region_key
)
SELECT *, CASE WHEN total_rows<>1 OR government_rows<>1 OR private_rows<>1 OR invalid_rows>0
 THEN 'NOT_COMPARABLE' WHEN total_count=government_count+private_count THEN 'MATCH'
 ELSE 'DIFFERENCE' END AS check_status
FROM counts ORDER BY parsed_year, region_key;

SELECT parsed_year, type_key, SUM(parsed_count) AS reported_regional_sum,
 COUNT_IF(parsed_count IS NULL) AS unparsed_counts
FROM hospital_profile GROUP BY parsed_year, type_key ORDER BY parsed_year, type_key;

SELECT _source_file, _run_id, COUNT(*) AS row_count,
 COUNT_IF(NULLIF(TRIM(_drive_file_id),'') IS NULL OR NULLIF(TRIM(_landing_file),'') IS NULL
  OR NULLIF(TRIM(_content_hash),'') IS NULL OR NULLIF(TRIM(_dataset_hash),'') IS NULL
  OR NULLIF(TRIM(_source_file),'') IS NULL OR NULLIF(TRIM(_run_id),'') IS NULL
  OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 COUNT_IF(NULLIF(TRIM(_rescued_data),'') IS NOT NULL) AS rescued_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM hospital_profile GROUP BY _source_file, _run_id;
