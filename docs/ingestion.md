# Google Drive to Bronze ingestion

## Purpose and current setup

The script reads prepared long-form datasets from Google Drive, preserves a source-file copy in a Unity Catalog Volume, and loads Bronze Delta tables. All source years are retained. Cleaning, numeric conversion, deduplication, and business validation belong in Silver.

| Item | Confirmed value |
| --- | --- |
| Script | `databricks/scripts/bronze/01_ingest_from_gdrive.py` |
| Execution | Manual Run button in the Databricks Python file editor |
| Catalog | `pondolens` |
| Schema | `dev_bronze` |
| Volume | `government_budget` |
| Volume path | `/Volumes/pondolens/dev_bronze/government_budget` |
| Audit table | `pondolens.dev_bronze.gdrive_ingestion_log` |
| Scheduling | No Databricks Job configured |
| Source folder ID | `1L_kvzPjQE60GjUvthLuwxbC3xKevHsoB` |

The notebook was removed; the Python script is the current entry point.

## Prerequisites

- Google Drive API enabled in the service account's Google Cloud project.
- Source folder shared with the service-account email as Viewer.
- Service-account JSON stored in Databricks Secrets: scope `pondolens`, key `gdrive-service-account`.
- Databricks execution environment provides `spark` and `dbutils`.
- Permission to read/write the Volume and create/write tables in the target schema.
- Required Python libraries installed in the script's execution environment.

The working setup installed libraries in the **Databricks Terminal**, not the local Mac terminal:

```bash
python -m pip install openpyxl google-api-python-client google-auth
```

Verify imports in that terminal:

```bash
python -c "import openpyxl, google.auth, googleapiclient; print('Dependencies available')"
```

Terminal installation has been used successfully for the current session. Persistence after compute/environment changes has not been verified. A missing-library error requires checking the environment used by the script. Never print credentials or commit the JSON key to Git.

## Parameters

| Parameter | Value or purpose |
| --- | --- |
| `catalog` | `pondolens` |
| `schema` | `dev_bronze` |
| `volume` | **`government_budget`**; exact existing Volume name |
| `drive_folder_id` | Source folder ID shown above |
| `dataset` | `all`, or one supported dataset name |
| `dry_run` | `true`: validate only; `false`: load and log |
| `secret_scope` | `pondolens` |
| `secret_key` | `gdrive-service-account` |
| `sheet_overrides_json` | `{}` or a JSON object mapping Drive file IDs to worksheet names |

The supplied code's original default spells the Volume `goverment_budget`. Override it with the confirmed value **`government_budget`** in execution parameters. The script does not create the Volume.

Example worksheet override:

```json
{"DRIVE_FILE_ID": "Long Form"}
```

The code supports notebook widgets and `--parameter value` arguments. For the current file-editor workflow, use the editor's execution parameters and confirm their effective values before running. The notebook widget interface is not required.

## Run step by step

1. Open the Git folder in Databricks Workspace.
2. Open `databricks/scripts/bronze/01_ingest_from_gdrive.py`.
3. Confirm dependencies are available in the script environment.
4. Set the target parameters above, select `dataset=all` or one dataset, and set `dry_run=true`.
5. Click Run. Review each `VALID` line and the final `Plan` output.
6. Resolve validation errors before continuing.
7. Change only `dry_run` to `false` and click Run again.
8. Review `SUCCESS`, `SKIPPED`, or failure output and inspect the audit log.
9. Verify table counts and rescued rows using the queries below.

A dry run downloads and parses files in memory but does not write landing files, tables, or audit records. Dataset-wide validation completes before table writes begin.

## Source routing and parsing

The script recursively traverses the source folder. New year files in an existing mapped folder do not require filename-specific configuration.

| Relative source folder | Target table |
| --- | --- |
| `01_agency_actuals` | `agency_actuals` |
| `02_sector_expenditure` | `sector_expenditure` |
| `03_regional_expenditure`, filename containing `gaa` | `regional_expenditure_gaa` |
| `03_regional_expenditure`, filename containing `obligation` | `regional_expenditure_obligations` |
| `04_population` | `population` |
| `05_development_indicators/01_quality_education` | `ched_graduates` |
| `05_development_indicators/02_unemployment_rate` | `unemployment_rate` |
| `05_development_indicators/03_poverty_incidence` | `poverty_incidence` |
| `05_development_indicators/04_service_access` | `service_access` |
| `05_development_indicators/05_grdp` | `grdp` |
| `05_development_indicators/06_grdp_capita` | `grdp_per_capita` |

- CSV files use the Python CSV parser with UTF-8 BOM support.
- XLSX/XLSM files use `openpyxl` with cached values; macros are not executed and formulas are not recalculated.
- Native Google Sheets are exported as XLSX before parsing.
- A configured worksheet override takes priority. Otherwise, the script requires exactly one candidate based on the worksheet name or year header.
- The first row supplies headers. Headers are normalized to lowercase with underscores.
- Source values are stored as strings; Excel `None` values remain NULL. Completely blank rows are skipped.
- Different file columns are combined with `unionByName(..., allowMissingColumns=True)`. Missing columns across files become NULL; schema differences are not automatically rescued.
- Unmapped/unsupported selected sources, unreadable files, invalid headers, malformed CSV syntax, or ambiguous worksheet selection fail validation.

## Source copies and lineage

Loaded files are saved under:

```text
/Volumes/pondolens/dev_bronze/government_budget/gdrive_landing/<drive_file_id>/<content_hash>.<extension>
```

| Bronze column | Purpose |
| --- | --- |
| `_drive_file_id` | Drive source identity |
| `_source_file` | Relative source path |
| `_landing_file` | Preserved file-copy path |
| `_source_modified_at` | Drive modification timestamp |
| `_source_sheet` | Selected worksheet, or NULL for CSV |
| `_content_hash` | SHA-256 of downloaded/exported bytes |
| `_header_map` | Normalized-to-original header mapping |
| `_dataset_hash` | Dataset snapshot fingerprint |
| `_run_id` | Execution ID |
| `_ingested_at` | Ingestion timestamp |
| `_rescued_data` | Original structurally mismatched row as JSON, or NULL |

## Rescued rows

This script implements custom rescue handling for **rows whose field count differs from the header count**. It is not Auto Loader's rescue mechanism.

For a mismatched row, `_rescued_data` stores the reason, source path, source row number, expected and actual field counts, headers, and all original values. Source data columns are set to NULL to avoid guessing their positions. Lineage is still populated, and the row remains in Bronze.

Valid rows have `_rescued_data=NULL`. Wrong numeric values are accepted as strings and must be reviewed in profiling/Silver. Rescue does not cover every parser or file error.

The table's total row count includes rescued rows. A successful load with rescued rows requires review before downstream use; it is not automatically marked FAILED. Existing tables without `_rescued_data` are reloaded once so the column is added.

## Snapshot replacement and reruns

The dataset fingerprint combines file IDs, relative paths, byte hashes, selected worksheets, and pipeline version.

A dataset is skipped when its fingerprint and row count match the current table and `_rescued_data` exists. Otherwise, the script overwrites the complete dataset table, including its schema, from all current mapped source files. It does not append rows.

Keep the complete intended source history in Drive. Removing one file from a dataset with remaining files removes that file's rows on the next reload. Removing every file in a dataset does not automatically clear its existing table because the dataset no longer appears in the load plan.

**Known limitation:** population is a native Google Sheet. Exported XLSX bytes may vary even when cell values are unchanged. The current byte-hash design can trigger unnecessary reloads. A stable parsed-content hash has not been implemented. Logs confirm repeated population reloads; the export-byte explanation remains the likely cause, not a separately verified source-content comparison.

Run only one writer at a time. Dataset commits are independent: failures do not roll back successful datasets. An error after a table commit, including audit logging failure, may report FAILED even though data was written.

## Audit trail

| Field | Meaning |
| --- | --- |
| `run_id` | Shared execution ID |
| `dataset` | Dataset name |
| `status` | SUCCESS, SKIPPED, or FAILED |
| `rows_loaded` | Snapshot rows written; 0 on skip; existing type remains string |
| `finished_at` | Logging time; existing type remains ISO timestamp text |
| `message` | Details/error text |
| `files_loaded` | Files committed in the snapshot, not new files added |
| `rescued_rows` | Rescued rows in the written snapshot; 0 on skip |
| `started_at` | Dataset processing start after shared validation |

Historical rows created before audit enhancements contain NULL in new fields. NULL does not establish that the rescued count was zero. Latest enhanced runs record numeric counts. A SKIPPED record's zero rescue count describes that run, not necessarily the existing table's quality.

## Observed execution results

The user-provided logs show the latest run `7c39dbfe19cf4c0f8a9160cfb93576f3` completed on October 12, 2026 at approximately 18:31–18:32 Philippine time. Ten datasets were SKIPPED. Population was SUCCESS with one file, 16,416 rows, and zero rescued rows.

The latest successful load counts reported in those logs are:

| Dataset | Files | Rows |
| --- | ---: | ---: |
| agency_actuals | 5 | 9,628 |
| ched_graduates | 1 | 4,843 |
| grdp | 1 | 95 |
| grdp_per_capita | 1 | 296 |
| population | 1 | 16,416 |
| poverty_incidence | 1 | 644 |
| regional_expenditure_gaa | 5 | 4,780 |
| regional_expenditure_obligations | 3 | 4,046 |
| sector_expenditure | 5 | 414 |
| service_access | 1 | 400 |
| unemployment_rate | 1 | 1,914 |
| **Total** | **25** | **43,476** |

These are historical log-derived counts, not a fresh direct table count. Latest successful enhanced loads reported zero rescued rows.

Agency actuals changed from six files/11,696 rows in run `46a8d68d06984bcdb85d0c4bbadb91d3` to five files/9,628 rows in run `93f8035a49d54936931fc0bd1a592a08`. The difference is one file and 2,068 rows. The logs establish a source snapshot change but do not identify the file or why it disappeared; confirm whether that change was intentional.

Rerun evidence supports skip detection for ten datasets. Population continues to reload. Full unchanged-source skip behavior across all datasets has not been verified. Zero rescue counts verify this structural check only, not overall data quality.

## Verification queries

Run these in the Databricks SQL editor.

### List target tables

```sql
SHOW TABLES IN pondolens.dev_bronze;
```

### Review the latest logged execution

```sql
SELECT run_id, dataset, status, files_loaded, rows_loaded,
       rescued_rows, started_at, finished_at, message
FROM pondolens.dev_bronze.gdrive_ingestion_log
WHERE run_id = (
    SELECT run_id
    FROM pondolens.dev_bronze.gdrive_ingestion_log
    ORDER BY finished_at DESC
    LIMIT 1
)
ORDER BY dataset;
```

### Inspect a table and its rescued rows

```sql
SELECT COUNT(*) AS total_rows,
       COUNT(_rescued_data) AS rescued_rows
FROM pondolens.dev_bronze.agency_actuals;

SELECT _source_file, _rescued_data
FROM pondolens.dev_bronze.agency_actuals
WHERE _rescued_data IS NOT NULL
LIMIT 20;
```

### Inspect source contributions

```sql
SELECT _drive_file_id, _source_file, COUNT(*) AS rows_per_file
FROM pondolens.dev_bronze.agency_actuals
GROUP BY _drive_file_id, _source_file
ORDER BY _source_file;
```

For rerun testing, record table counts before and after running with unchanged sources. Expect SKIPPED and zero files/rows loaded for stable files. Unchanged counts alone do not prove unchanged values or absence of pre-existing duplicates. Population currently requires separate review because of the export-hash limitation.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| `ModuleNotFoundError` | Install/check dependencies in the Databricks script environment |
| `UC_VOLUME_NOT_FOUND` | Run `SHOW VOLUMES IN pondolens.dev_bronze;` and use exact Volume name `government_budget` |
| Drive permission/access failure | Verify folder sharing, credential secret, and enabled Drive API |
| Ambiguous worksheet | Provide the intended tab through `sheet_overrides_json` |
| Validation failure | Fix the reported source/structure issue, then repeat dry run |
| Nonzero rescued rows | Inspect `_rescued_data`; repair the source or define Silver treatment |
| Population SUCCESS on unchanged rerun | Review known Google Sheets export-hash limitation |
| Unexpected decrease in rows/files | Review current Drive snapshot and per-file contributions |
| FAILED after loading | Inspect both the table and audit/error output; do not assume rollback |

Do not delete the Volume or drop tables to resolve routine dependency or parameter errors.
