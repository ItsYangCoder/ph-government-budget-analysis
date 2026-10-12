# Bronze Ingestion

## Purpose

Load prepared long-form files from Google Drive into Bronze Delta tables. Preserve source copies and lineage. Retain all source years; cleaning and business validation belong in Silver.

## Setup

| Setting | Value |
| --- | --- |
| Script | `databricks/scripts/bronze/01_ingest_from_gdrive.py` |
| Execution | Manual Run in the Databricks Python file editor |
| Catalog | `pondolens` |
| Schema | `dev_bronze` |
| Volume | `government_budget` |
| Source folder ID | `1L_kvzPjQE60GjUvthLuwxbC3xKevHsoB` |
| Audit table | `pondolens.dev_bronze.gdrive_ingestion_log` |

Enable the Google Drive API and share the source folder with the service account as Viewer. Store credentials in Databricks Secrets: scope `pondolens`, key `gdrive-service-account`. The script requires access to `spark`, `dbutils`, the schema, and the Volume.

Missing `openpyxl`, `google-api-python-client`, and `google-auth` packages are installed by the script. Installation requires package access and environment write permission. Never store credentials in Git.

## Parameters and Usage

| Parameter | Value |
| --- | --- |
| `catalog` | `pondolens` |
| `schema` | `dev_bronze` |
| `volume` | `government_budget` |
| `drive_folder_id` | Source folder ID above |
| `dataset` | `all` or one dataset |
| `dry_run` | `true`: validate only; `false`: load and log |
| `secret_scope` | `pondolens` |
| `secret_key` | `gdrive-service-account` |
| `sheet_overrides_json` | `{}` or a mapping of Drive file IDs to worksheet names |

1. Open the script and set parameters.
2. Run with `dry_run=true`; resolve validation errors.
3. Run with `dry_run=false` to load.
4. Review run output and the audit log.

## Dataset Mapping and Counts

Indicator folders below are under `05_development_indicators`.

| Source folder | Table | Files | Rows |
| --- | --- | ---: | ---: |
| `01_agency_actuals` | `agency_actuals` | 5 | 9,628 |
| `02_sector_expenditure` | `sector_expenditure` | 5 | 414 |
| `03_regional_expenditure`, filename contains `gaa` | `regional_expenditure_gaa` | 5 | 4,780 |
| `03_regional_expenditure`, filename contains `obligation` | `regional_expenditure_obligations` | 3 | 4,046 |
| `04_population` | `population` | 1 | 16,416 |
| Indicator: `01_quality_education` | `ched_graduates` | 1 | 4,843 |
| Indicator: `02_unemployment_rate` | `unemployment_rate` | 1 | 1,914 |
| Indicator: `03_poverty_incidence` | `poverty_incidence` | 1 | 644 |
| Indicator: `04_service_access` | `service_access` | 1 | 400 |
| Indicator: `05_grdp` | `grdp` | 1 | 95 |
| Indicator: `06_grdp_capita` | `grdp_per_capita` | 1 | 296 |
| **Total** | **11 datasets** | **25** | **43,476** |

Counts confirmed on October 12, 2026. Subfolders are scanned recursively. New files in mapped folders are included automatically.

## Processing

- CSV files are parsed directly. XLSX/XLSM files use cached cell values; macros are not executed.
- Google Sheets are exported as XLSX. Worksheet overrides take priority; ambiguous selection fails validation.
- Headers are normalized to lowercase with underscores. Source values remain strings; blank Excel cells remain NULL. Blank rows are skipped.
- Different file schemas are combined by column name; missing columns become NULL.
- Selected files are validated before writes. Unreadable files, invalid headers, unsupported sources, and parser errors stop validation.

## Rescued Data

Rows with missing or extra fields are retained in `_rescued_data` as JSON, including their original values and source row. Their source columns are set to NULL; lineage remains populated. Valid-length rows have `_rescued_data=NULL`.

Rescued rows count toward total rows and `rescued_rows` in the audit log. They do not automatically fail ingestion. Numeric validity, missing values, duplicates, and business rules are checked in Silver.

## Source Copies and Reruns

Source copies are saved under `/Volumes/pondolens/dev_bronze/government_budget/gdrive_landing/<drive_file_id>/<content_hash>.<extension>`.

Lineage includes file ID, source path, landing path, modification time, worksheet, byte hash, original header mapping, dataset fingerprint, run ID, and load time.

Stored files use byte hashes for change detection. Google Sheets use parsed-content hashes to avoid reloads caused only by export-byte changes. The byte hash is retained for source-file lineage.

Matching fingerprint and row count, with the rescue column present, results in `SKIPPED`. Changed datasets replace their complete table snapshot and schema; rows are not appended.

Keep complete source history in Drive. Removing a file removes its rows on the next reload. Removing every file for a dataset does not automatically clear its existing table. Run one writer at a time. Dataset commits are independent; failures do not roll back completed writes.

## Audit Trail

| Field | Meaning |
| --- | --- |
| `run_id` | Execution ID |
| `dataset` | Dataset name |
| `status` | SUCCESS, SKIPPED, or FAILED |
| `files_loaded` | Files written in the snapshot; 0 on skip |
| `rows_loaded` | Snapshot rows written; 0 on skip; stored as string |
| `rescued_rows` | Rescued rows written; 0 on skip |
| `started_at` | Dataset processing start after validation |
| `finished_at` | Log time, stored as ISO text |
| `message` | Error/details |

Older records may have NULL in added fields. Skip counts describe that run, not existing table quality. A failure after a table write does not imply rollback.

## Verified Results

| Check | Result | Run ID |
| --- | --- | --- |
| Source and table counts | 25 files, 11 datasets, 43,476 rows confirmed | `39250e01a86e4ef093baffaaca1e8b3f` |
| Drive-to-Bronze rescue | 3 test rows; 2 rescued; original values preserved | `3868a748ca17469a9d5539c0af94f0cb` |
| Population unchanged rerun | SKIPPED with parsed-content hashing | `e9f4626f91994054ba61545177458083` |
| Full unchanged rerun | All 11 datasets SKIPPED | `39250e01a86e4ef093baffaaca1e8b3f` |

Rescue testing used `bronze_test`. Test files were excluded from the final regular source listing. These checks verify ingestion behavior, not overall business-data quality.
