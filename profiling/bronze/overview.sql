-- Shared Bronze completeness and lineage overview. Persistent tables are read-only.
-- All registered tables must exist. Filter scope in the returned results, not source rows.
-- Counts are observations, not automatic acceptance thresholds.
SELECT 'agency_actuals' AS dataset, 'reference_only' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.agency_actuals
UNION ALL
SELECT 'completion_rate' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.completion_rate
UNION ALL
SELECT 'grdp_per_capita' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.grdp_per_capita
UNION ALL
SELECT 'hospital' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.hospital
UNION ALL
SELECT 'population' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.population
UNION ALL
SELECT 'poverty_incidence' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.poverty_incidence
UNION ALL
SELECT 'regional_appropriation' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.regional_appropriation
UNION ALL
SELECT 'region_boundaries' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.region_boundaries
UNION ALL
SELECT 'regional_obligation' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.regional_obligations
UNION ALL
SELECT 'service_access' AS dataset, 'reference_only' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.service_access
UNION ALL
SELECT 'unemployment_rate' AS dataset, 'active' AS scope, COUNT(*) AS total_rows,
 COUNT(DISTINCT _source_file) AS source_files,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
 COUNT_IF(NULLIF(TRIM(_drive_file_id), '') IS NULL
   OR NULLIF(TRIM(_source_file), '') IS NULL
   OR NULLIF(TRIM(_landing_file), '') IS NULL
   OR NULLIF(TRIM(_content_hash), '') IS NULL
   OR NULLIF(TRIM(_dataset_hash), '') IS NULL
   OR NULLIF(TRIM(_run_id), '') IS NULL
   OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion, MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.unemployment_rate
ORDER BY scope, dataset;
