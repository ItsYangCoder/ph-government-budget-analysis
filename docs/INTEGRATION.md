# PondoLens ingestion refactor

This is a repository overlay, not a replacement repository. Copy `src/`,
`platform/databricks/runners/run_ingestion.py`, and `tests/unit/` into your
`refactor/modularize-gdrive-ingestion` branch. Merge `pyproject.toml` with your
existing project configuration if that file already exists. Keep existing docs,
CI, models, profiling files, and the original ingestion script during validation.

## Run on Databricks

1. Check out the branch with all the supplied folders. Uploading only the runner
   is insufficient: it imports the package under `src/`.
2. The runner installs missing `openpyxl`, `google-api-python-client`,
   `google-auth`, and `databricks-sdk` before initialization, matching the latest
   script. This needs package-index access and permission to install. Preinstalled
   packages are retained. For repeatable Jobs, provision dependencies in the task
   environment. Spark comes from Databricks; it is not bundled in this archive.
3. Open `platform/databricks/runners/run_ingestion.py` in the same interactive
   execution context that supported widgets for your original script.
4. Run without explicit CLI parameters. The same nine widgets are created:
   catalog, schema, volume, drive_folder_id, secret_scope, secret_key, dataset,
   dry_run, sheet_overrides_json. Native widget support depends on the execution
   context; unsupported contexts raise an error rather than silently loading.
5. Validate with `dataset=all`, `dry_run=true`. Then load with `dry_run=false`.
6. Run again unchanged and verify `SKIPPED` results, row counts, table columns,
   and the ingestion log against the original script.

For a Job Python script task, target the runner and use:

```json
["--dataset", "all", "--dry_run", "true"]
```

Set maximum concurrent runs to **1**. Explicit recognized CLI parameters take
precedence over widgets, as before. Install the package on worker/remote
execution environments when the repository source tree is not present.

## Package and command-line usage

```bash
python -m pip install -e .
pondolens --dataset all --dry_run true
```

This CLI still requires a working Databricks Spark execution environment. Running
it on an ordinary laptop does not create a remote Databricks session. The refactor
separates responsibilities; it does not implement a local storage backend or
migrate transformations to dbt.

## Offline code checks

```bash
PYTHONPATH=src python -m unittest discover -s tests/unit -v
```

These tests mock dependency installation and do not authenticate to Drive, create live catalog objects, or write
actual Delta tables. They cover parsing, widget parameters, safeguards, dry runs,
storage statement order, audit columns, mocked writes, and unchanged reruns.

## Files and responsibilities

| File | Responsibility |
| --- | --- |
| `src/pondolens/cli.py` | CLI entry point |
| `src/pondolens/common/config.py` | Existing defaults and parameter validation |
| `src/pondolens/common/dependencies.py` | Install missing dependencies before runner/CLI initialization |
| `src/pondolens/common/hashing.py` | Original dataset fingerprint algorithm |
| `src/pondolens/ingestion/pipeline.py` | Coordinate source validation and dataset loads |
| `src/pondolens/ingestion/google_drive.py` | Authentication, listing, traversal, downloads |
| `src/pondolens/ingestion/routing.py` | Route source paths and extensions |
| `src/pondolens/ingestion/parsers.py` | CSV, Excel, completion-rate, GeoJSON parsing |
| `src/pondolens/ingestion/validation.py` | Replacement guards and preflight checks |
| `src/pondolens/storage/databricks.py` | Runtime initialization, storage provisioning, landing files, Delta writes, ingestion logs |
| `platform/databricks/runners/run_ingestion.py` | Native widgets and Databricks entry point |

## Preserved behavior

- Same datasets, source routing, table names, string values and rescued records.
- Same content/dataset hash serialization and pipeline version.
- Same audit columns and ingestion-log schema.
- Catalog, schema, managed volume creation only on load runs, after preflight.
- Validation runs do not write landing files, tables, or logs.
- Existing secret authentication by default; optional file authentication via
  CLI. The existing credentials-file path default is retained for compatibility;
  no credential contents are included. Override the path for another user.
- Changed datasets overwrite their complete current Drive snapshot. Missing
  source files and removed columns remain blocked unless explicitly allowed.
- Writes are atomic per table, not across the whole pipeline. Audit logging can
  fail separately from a successful table commit; inspect the target on errors.

## Intentional refactor changes

- Mutable module-global runtime state is replaced by an independent context for
  each run. Spark and dbutils can be injected into `run()`.
- Widgets live in the Databricks runner. The package CLI uses defaults/arguments
  and does not attempt widget initialization.
- Dataset writes now live in the storage module; fingerprinting is a pure helper.

Keep current executable paths until your Jobs and imports point to the new
runner and a live load plus unchanged rerun pass. This archive does not modify
remote Jobs or your GitHub repository.

## Dataset names updated

CHED graduates, GRDP, and sector expenditure are excluded, including their files during all-dataset runs. GRDP per capita is retained. New target names are `hospital`, `regional_appropriation`, and `regional_obligations`. Original Drive folder/file names remain supported. Existing old database tables are not renamed or deleted automatically. Update downstream consumers separately and reconcile results before retiring old tables. A renamed target is built from the current source snapshot; its first run will load rather than skip. If an interactive dataset widget retains an old value, select `all` or the new name before running.

## Source of this revision

Refactored from the latest uploaded `01_ingest_from_gdrive_no_sector(1).py`.
The original nine widgets, dependency bootstrap, source exclusions, renamed
targets, parsing behavior, and fingerprint algorithm are retained. Offline
comparison against that script passed for CSV, rescued rows, completion-rate,
Excel, and GeoJSON sample inputs. Live Drive/Spark validation remains required.
