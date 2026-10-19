# PondoLens

### Philippine Government Budget Analysis

PondoLens is a data engineering capstone that brings Philippine government budget data and regional indicators into a shared analytical workflow. It helps readers explore where public funds are allocated, where appropriation and obligation figures differ, and how regional spending compares with selected development indicators.

The main analytical scope is **2021–2025**. Actual coverage varies by dataset; missing years and changes in regional coverage are documented rather than filled with assumed values.

**Team:** Razz, Rhea, Anji, Mia, and Joy  
**Program:** FTW Foundation — Batch 12, Data Engineering

## Business questions

| Question | Focus |
|---|---|
| **Q1. Where does the money go across agencies and regions?** | Compare allocations across agencies, regions, and years. |
| **Q2. Where do budget execution gaps appear?** | Compare regional appropriations and obligations at a compatible grain. |
| **Q3. How does regional spending compare with development indicators?** | Examine spending alongside GRDP per capita, unemployment, and service access. |

Completion rate and government hospital counts provide additional education and health context as their transformations and source definitions are validated.

An appropriation–obligation difference does not, by itself, explain why a gap exists or establish misuse of funds. Indicator comparisons describe patterns and associations; they do not prove that spending caused an outcome.

## Start here

| Looking for… | Open |
|---|---|
| How ingestion works and how to run it | [Ingestion guide](docs/ingestion.md) |
| Raw-data profiling and treatment proposals | [Bronze profiling](profiling/bronze/) |
| Completion rate findings | [Completion rate profiling](profiling/bronze/completion_rate/findings.md) |
| Hospital findings | [Hospital profiling](profiling/bronze/hospital/findings.md) |
| Completion rate Silver rules and dictionary | [Completion rate documentation](docs/silver/completion_rate.md) |
| Hospital Silver rules and dictionary | [Hospital documentation](docs/silver/hospital.md) |
| Region mapping | [Crosswalk documentation](docs/crosswalk.md) |
| Executable transformation files | [Silver folder](dbt/models/02_silver/) |

## Pipeline overview

Source reports are prepared as structured files before entering the ingestion workflow. This repository currently contains the Google Drive ingestion implementation, not the PDF/Excel extraction scripts used to prepare those files.

| Stage | What happens | Location |
|---|---|---|
| **Source files** | Prepared CSV, Excel, Google Sheets, and GeoJSON inputs are read from Google Drive. | Configured Drive folder |
| **Ingestion** | Python authenticates, discovers files, routes datasets, parses records, and validates the load plan. | `src/pondolens/ingestion/` |
| **Bronze** | Original source values, landing files, and ingestion lineage are retained. | `pondolens.dev_bronze` |
| **Profiling** | Dataset checks identify missing values, duplicates, coverage gaps, and proposed treatments. | `profiling/bronze/` |
| **Silver** | SQL standardizes types, labels, region mappings, and dataset-specific rules. | `pondolens.dev_silver` |
| **Gold and serving** | Dimensions, facts, and analytical queries support the business questions. Repository migration is still in progress. | Planned folders under `dbt/models/03_gold/`, `analytics/`, and `dashboard/` |

The project uses a medallion approach. Python ingestion logic is separated from the Databricks entry point, while current storage and transformations still depend on Databricks and Spark.

## Current repository status

Status below reflects the files present in `dev` on **19 October 2026**. Workspace assets and repository implementation may differ during migration.

| Component | Status |
|---|---|
| Modular Google Drive ingestion | Implemented; live load, unchanged rerun, and record comparison documented for 11 datasets. |
| Bronze profiling | Present for several datasets; completion rate and hospital include dictionaries and findings. |
| Bronze source YAML | Present for completion rate and hospital; definitions still need consolidation during dbt setup. |
| Completion rate Silver | SQL and documentation committed; transformation-stage results recorded. Final migration and load behavior require execution verification. |
| Hospital Silver | SQL notebook and documented validation results committed. Current creation query does not refresh an existing table. |
| dbt execution | Not configured yet; no `dbt_project.yml` or connection profile is committed. Current Silver files are Databricks SQL scripts/notebooks, not runnable dbt models. |
| Gold, DQ monitoring, analytics, and dashboard folders | Placeholders in the current repository; do not represent completed deployments. |
| Orchestration | No Prefect or other orchestrator implementation is committed. Databricks Job task setup is described in the ingestion guide. |
| CI | GitHub Actions checks Python syntax and notebook structure in configured scan folders. Offline unit tests are available separately. |

## Data sources and Bronze tables

Source families include **DBM budget reports**, **PSA/OpenSTAT indicators**, and **DOH hospital statistics reported through the source publication**. Exact file references, source labels, and coverage belong in the dataset documentation.

| Bronze table | Contents |
|---|---|
| `agency_actuals` | Agency actual expenditure records |
| `regional_appropriation` | Regional appropriation records from GAA files |
| `regional_obligations` | Regional obligation records |
| `population` | Population projections |
| `unemployment_rate` | Unemployment indicators |
| `poverty_incidence` | Poverty incidence indicators |
| `service_access` | Drinking water, electricity, and internet access indicators |
| `grdp_per_capita` | GRDP per capita |
| `completion_rate` | Completion percentages by location, education level, and sex |
| `region_boundaries` | Regional geographic boundaries |
| `hospital` | Regional government regulated hospital counts in the current snapshot |

CHED graduates, GRDP, and sector expenditure are excluded from the current ingestion scope. GRDP per capita remains included.

Default landing volume: `/Volumes/pondolens/dev_bronze/government_budget`.

## Repository guide

| Path | Responsibility |
|---|---|
| `src/pondolens/ingestion/` | Drive access, dataset routing, parsing, validation, and pipeline coordination |
| `src/pondolens/storage/` | Databricks runtime, landing-file writes, Delta writes, and ingestion logs |
| `src/pondolens/common/` | Configuration, dependency bootstrap, and dataset fingerprints |
| `platform/databricks/runners/` | Databricks ingestion entry point and widgets |
| `dbt/models/01_bronze/` | Bronze source YAML definitions |
| `dbt/models/02_silver/` | Current Silver SQL scripts and notebooks awaiting dbt migration |
| `dbt/models/03_gold/` | Reserved for Gold dimensions and facts |
| `dbt/models/04_monitoring/` | Reserved for monitoring models |
| `profiling/bronze/` | Dataset profiling queries/notebooks, dictionaries, and findings |
| `docs/` | Ingestion, crosswalk, and transformation documentation |
| `data_quality/` | Reserved for reusable DQ rules and queries |
| `analytics/` | Reserved for analytical queries |
| `dashboard/` | Reserved for dashboard documentation and assets |
| `tests/` | Offline unit tests and Databricks ingestion comparison script |
| `scripts/check_code.py` | Python syntax and notebook validation |
| `.github/workflows/ci.yml` | Automated repository code checks |

## Run Bronze ingestion

### Requirements

- A checkout of this repository inside Databricks, including `src/pondolens/`.
- Spark compute with Unity Catalog and managed storage configured.
- Permission to use and, when absent, create the target catalog, schema, volume, and tables.
- A Google service account with read access to the source folder.
- A Databricks secret containing the service-account JSON.
- Package installation access, or dependencies provisioned in the task environment.

### Interactive run

1. Open [`platform/databricks/runners/run_ingestion.py`](platform/databricks/runners/run_ingestion.py) from the repository checkout.
2. Review the nine widgets: `catalog`, `schema`, `volume`, `drive_folder_id`, `secret_scope`, `secret_key`, `dataset`, `dry_run`, and `sheet_overrides_json`.
3. Start with `dataset=all` and `dry_run=true`. Review the validated file plan and any errors.
4. Confirm the target, then set `dry_run=false` and rerun to load.
5. Review the ingestion log for `SUCCESS`, `SKIPPED`, or failure details.

A dry run does not create storage objects or write target data. Load runs create missing catalog/schema/volume objects after preflight validation. Unchanged dataset fingerprints and matching row counts produce `SKIPPED` results.

```sql
SELECT *
FROM pondolens.dev_bronze.gdrive_ingestion_log
ORDER BY finished_at DESC;
```

For Job arguments, limits, safeguards, and recorded validation, see the [ingestion guide](docs/ingestion.md). Configure maximum concurrent runs as **1**.

## Run Silver transformations

The shared crosswalk must be populated before either current Silver transformation runs.

| Dataset | Executable file | Notes |
|---|---|---|
| Completion rate | [completion_rate.sql](dbt/models/02_silver/completion_rate/completion_rate.sql) | Run statements in order in a Databricks SQL notebook/session and stop on the first error. Supports updates, inserts, and scoped snapshot deletions. |
| Hospital | [Silver notebook](dbt/models/02_silver/hospital/silver_hospital.sql.dbquery.ipynb) | Current SQL uses CREATE TABLE IF NOT EXISTS; rerunning it does not refresh an existing table. |

Completion rate uses IDs starting at 8,000,001 and retains missing observations. Run it only after a complete Bronze snapshot with one target writer: an incomplete source can trigger deletions. MAX-based ID allocation can reuse deleted highest IDs. See the [dataset documentation](docs/silver/completion_rate.md) for the complete behavior and verification status.

These files currently run in Databricks. Do not use `dbt run` until the dbt project is configured and the scripts are converted into dbt models.

## Local development and checks

Use Python **3.12** to match the current CI environment. From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m pip install 'nbformat>=5.10,<6'

python scripts/check_code.py
python -m pytest -q tests/unit
```

Offline tests use mocks and do not require live Drive or Spark connections. They verify ingestion behavior; they do not execute the Silver SQL against Databricks. The notebook checker scans configured folders and is not a full SQL validator.

[`tests/integration/validate_ingestion.py`](tests/integration/validate_ingestion.py) compares original and refactored tables in Databricks. Review its configured schemas before running it.

Installing the Python package on a laptop does not create a remote Spark session. A local storage backend is not implemented.

## Data quality and known limitations

- Completion rate has numeric observations for 2021–2024, with NIR missing in 2021–2023. The 2025 source column contains only missing markers in the profiled snapshot.
- Hospital data covers 2021–2024, Government hospitals only, and 17 historical source regions. NIR is not separately listed.
- Region aliases standardize labels; they do not resolve differences in historical boundaries.
- Completion percentages must not be summed or combined across aggregate and sex-specific categories.
- Hospital counts do not measure beds, staffing, capacity, or quality of care.
- Successful ingestion and zero rescued rows do not establish business correctness. Dataset-level checks remain necessary.
- Central DQ result tables and a DQ dashboard are planned, not implemented by the current placeholder folders.

## Team workflow

1. Start a task branch from the latest `dev`.
2. Keep code and dataset documentation together in the change.
3. Run relevant checks and record Databricks validation results.
4. Open a pull request targeting `dev` and review conflicts before merging.
5. Delete a task branch after confirming its work is merged. Preserve branches with unmerged team work.

For new Bronze profiling work, use `profiling.sql`, `data_dictionary.md`, and `findings.md` under the dataset folder. Existing notebooks are being consolidated into this convention. Silver documentation belongs in `docs/silver/<dataset>.md`.

Keep tokens, passwords, and service-account keys outside Git. Use Databricks secrets for runtime credentials.

## Next milestones

- Verify the final completion rate load, ID assignment, repeat runs, and controlled source changes.
- Consolidate and version the shared region crosswalk, including required completion rate aliases.
- Make hospital loading refreshable and validate its failure handling.
- Configure dbt and migrate validated transformations into models with descriptions and tests.
- Bring the remaining Silver and Gold transformations into the repository.
- Implement DQ monitoring, analytical queries, dashboard documentation, and orchestration.
