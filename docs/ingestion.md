# PondoLens Bronze Ingestion

The ingestion pipeline reads the project's long-form Google Drive files and
loads them into Bronze Delta tables in Databricks. The implementation is split
into reusable Python modules, with one Databricks entry point.

**Validation status:** the refactored pipeline completed a live load, an unchanged
rerun, and source-record comparison for all 11 datasets on October 19, 2026
(Philippine time). Results apply to the tested source snapshot.

## Entry point and requirements

Run this file from the checked-out repository:

```text
platform/databricks/runners/run_ingestion.py
```

Keep the repository's `src/pondolens/` package alongside the runner. Uploading
only the runner is insufficient.

Requirements:

- Databricks Spark compute with Unity Catalog and managed storage configured.
- Permissions to use the target catalog, schema, volume, and tables, and create
  missing objects when required.
- A Google service account with read access to the source Drive folder.
- Read access to the configured service-account secret.

The runner installs missing `openpyxl`, `google-api-python-client`, `google-auth`,
and `databricks-sdk` packages before initialization. This requires package-index
access and permission to install. Existing packages are retained. For repeatable
Jobs, configure dependencies in the task environment. Spark is supplied by
Databricks.

## Interactive parameters

Run without recognized CLI arguments to use the native Databricks widgets.

| Widget | Default | Purpose |
| --- | --- | --- |
| `catalog` | `pondolens` | Target catalog |
| `schema` | `dev_bronze` | Target Bronze schema |
| `volume` | `government_budget` | Landing-file volume within the target schema |
| `drive_folder_id` | `1L_kvzPjQE60GjUvthLuwxbC3xKevHsoB` | Source folder ID |
| `secret_scope` | `pondolens` | Service-account secret scope |
| `secret_key` | `gdrive-service-account` | Service-account JSON secret key |
| `dataset` | `all` | All supported datasets or one dataset |
| `dry_run` | `true` | Validate without writing target data |
| `sheet_overrides_json` | `{}` | File-ID-to-sheet-name overrides |

Widgets may retain previously selected values. Check the target schema and
`dry_run` before every run. Native widget availability depends on the execution
context; unsupported contexts raise an error.

Additional settings remain available through CLI arguments, including
`auth_mode`, `service_account_path`, replacement overrides, and resource limits.
Secret authentication is the default. File authentication requires an explicitly
selected file mode and an explicit absolute `--service_account_path` for the execution identity. The path has no default.
Keep credential contents outside Git.

## Run the pipeline

1. Open the runner and select `dataset=all`, `dry_run=true`.
2. Confirm `Connected!`, the expected `VALID` messages, and a complete `Plan` with
   no exception. A dry run does not write landing files, tables, or audit logs,
   and does not create catalog, schema, or volume objects.
3. Confirm the intended schema, then set `dry_run=false` and rerun.
4. Confirm `SUCCESS` or `SKIPPED` for every planned dataset and `Completed run`.
5. Inspect the ingestion log for the completed run.

On load runs, the pipeline uses `CREATE ... IF NOT EXISTS` for the catalog,
schema, and managed volume after preflight validation. It then stores source
files under the volume's `gdrive_landing/` directory and writes the Bronze tables.

Regular target:

```text
pondolens.dev_bronze
/Volumes/pondolens/dev_bronze/government_budget
```

For isolated testing, use **`pondolens.dev_bronze_refactor_test`** in
widgets, Job parameters, and verification queries.

## Supported datasets

| Bronze table | Source category |
| --- | --- |
| `agency_actuals` | Agency actuals |
| `regional_appropriation` | Regional GAA appropriation files |
| `regional_obligations` | Regional obligation files |
| `population` | Population projections |
| `unemployment_rate` | Unemployment indicators |
| `poverty_incidence` | Poverty indicators |
| `service_access` | Water, electricity, and internet indicators |
| `grdp_per_capita` | GRDP per capita |
| `completion_rate` | Education completion indicators |
| `region_boundaries` | Regional GeoJSON boundaries |
| `hospital` | DOH-regulated hospital data |

CHED graduates, GRDP, and sector expenditure are excluded from ingestion,
including during `dataset=all` runs. GRDP per capita remains included.
Original Drive folder and file names remain supported.

Earlier target names were `regional_expenditure_gaa`,
`regional_expenditure_obligations`, and `doh_regulated_hospitals`. The current
pipeline writes to the names listed above. It does not rename or delete old
tables automatically. Update downstream references where applicable.

## Writes, hashes, and audit trail

- A changed dataset is replaced from all its current selected Drive files.
- Missing previously ingested source files or removed source columns block
  replacement unless the corresponding override is explicitly enabled.
- Source inventory changes during validation block the load.
- File-size and row limits constrain driver-side parsing.
- Unchanged dataset hashes and row counts cause a `SKIPPED` result.
- Source files are still read and parsed on unchanged reruns to compute hashes.
- Commits are atomic per table, not across the complete pipeline. A failed run
  may have already committed other tables; review the log before retrying.

Bronze lineage columns:

```text
_drive_file_id
_source_file
_landing_file
_source_modified_at
_source_sheet
_content_hash
_header_map
_dataset_hash
_run_id
_ingested_at
_rescued_data
```

The audit table is `pondolens.dev_bronze.gdrive_ingestion_log`. It records each
dataset's status, loaded row count, file count, rescued row count, and timing.
Audit logging can fail separately from a table commit; inspect the target table
when investigating failures.

Example for regular runs:

```sql
SELECT *
FROM pondolens.dev_bronze.gdrive_ingestion_log
ORDER BY finished_at DESC;
```

## Recorded validation

The user executed the live checks in Databricks and supplied the results.

| Check | Observed result |
| --- | --- |
| Offline tests | 18 passed |
| Offline parser/hash comparison | Sample CSV, rescued records, completion-rate, Excel, and GeoJSON outputs matched the latest standalone script |
| Live dry run | 23 files planned for 11 tables |
| Initial live load | All 11 datasets reported `SUCCESS`; zero rescued rows in the ingestion log |
| Unchanged live rerun | All 11 datasets reported `SKIPPED` |
| Record comparison | All 11 datasets reported `MATCH`; zero differences in both directions |

Live run identifiers:

- Initial load: `89b3244efba54029adb6cecaacc47efa`
- Unchanged rerun: `19a70355763c42049a2927780c8aa190`

Record comparison used original schema `pondolens.dev_bronze` and refactored
schema `pondolens.dev_bronze_refactor_test`.
It compared source columns and
`_rescued_data` as strings using `EXCEPT ALL` in both directions, preserving
record multiplicity. Other ingestion metadata, such as run IDs, timestamps,
landing paths, and hash columns, was excluded from this live comparison.

| Dataset | Original rows | Refactored rows | Original-only rows | Refactored-only rows | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| `agency_actuals` | 9,628 | 9,628 | 0 | 0 | MATCH |
| `regional_appropriation` | 4,780 | 4,780 | 0 | 0 | MATCH |
| `regional_obligations` | 4,345 | 4,345 | 0 | 0 | MATCH |
| `population` | 16,416 | 16,416 | 0 | 0 | MATCH |
| `unemployment_rate` | 1,914 | 1,914 | 0 | 0 | MATCH |
| `poverty_incidence` | 644 | 644 | 0 | 0 | MATCH |
| `service_access` | 400 | 400 | 0 | 0 | MATCH |
| `grdp_per_capita` | 296 | 296 | 0 | 0 | MATCH |
| `completion_rate` | 171 | 171 | 0 | 0 | MATCH |
| `region_boundaries` | 18 | 18 | 0 | 0 | MATCH |
| `hospital` | 68 | 68 | 0 | 0 | MATCH |

These results verify loading, unchanged-data detection, and compared-record
parity for this snapshot. Zero rescued rows indicates no parser-rescued
column-count mismatches; it does not establish completeness, uniqueness, or
business validity. Those require the project's separate DQ checks.

## Code layout

| File | Responsibility |
| --- | --- |
| `src/pondolens/cli.py` | Command-line entry point |
| `src/pondolens/common/config.py` | Defaults and parameter validation |
| `src/pondolens/common/dependencies.py` | Missing-package setup |
| `src/pondolens/common/hashing.py` | Dataset fingerprints |
| `src/pondolens/ingestion/pipeline.py` | Coordinate validation and loads |
| `src/pondolens/ingestion/google_drive.py` | Authentication, listing, traversal, and downloads |
| `src/pondolens/ingestion/routing.py` | Dataset routing and exclusions |
| `src/pondolens/ingestion/parsers.py` | CSV, Excel, completion-rate, and GeoJSON parsing |
| `src/pondolens/ingestion/validation.py` | Preflight checks and replacement safeguards |
| `src/pondolens/storage/databricks.py` | Runtime setup, landing files, Delta writes, and logs |
| `platform/databricks/runners/run_ingestion.py` | Widgets and Databricks execution |

Each run has an independent context rather than mutable module-global runtime
state. This refactor still uses Databricks storage; it does not implement a local
storage backend or convert Silver/Gold transformations to dbt.

## Jobs and command-line execution

For a Databricks Job Python script task, target the runner. Example validation
arguments:

```json
["--dataset", "all", "--schema", "dev_bronze", "--dry_run", "true"]
```

After reviewing validation, change `true` to `false` for a load. Set maximum
concurrent runs to **1**. Recognized CLI arguments take precedence over widgets.
Update existing Job task paths when adopting the new runner.

To install the package from the repository root:

```bash
python -m pip install -e .
pondolens --dataset all --dry_run true
```

The CLI requires a working Databricks Spark execution environment. Installing
it on an ordinary laptop does not establish a remote Databricks session.

## Offline checks

From the repository root:

```bash
PYTHONPATH=src python -m unittest discover -s tests/unit -v
```

The tests mock package installation and external services. They cover parsing,
routing, parameter widgets, safeguards, dry runs, storage creation order, audit
columns, mocked writes, and unchanged reruns. Repeat relevant live validation
when parsing, routing, schema, or write behavior changes.
