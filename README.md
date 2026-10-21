# PondoLens

### Philippine Government Budget Analysis

PondoLens is an end-to-end data engineering capstone developed through the FTW Foundation Data Engineering Scholarship Program, Batch 12. It brings Philippine government budget data and regional indicators into a shared analytical workflow. Python loads prepared source files from Google Drive into Databricks Bronze tables. dbt transforms those records into Silver tables and Gold dimensions and facts for analysis.

The main analytical scope is **2021–2025**. Coverage varies by dataset. Missing years, source markers, and changes in regional coverage are documented rather than replaced with assumed values.

## Analytics

- **AP 1:** Where does the money go across departments and regions?
- **AP 2:** How does regional government spending compare to population?
- **AP 3:** How does regional government spending compare with GRDP per capita?

Budget allocation uses appropriations. Spending comparisons use obligations, which are commitments and are not the same as cash payments.

### Data sources and comparison

| Data | Official source | How it is used |
|---|---|---|
| Regional budget and obligations | [DBM — Budget of Expenditures and Sources of Financing](https://www.dbm.gov.ph/index.php/test/1205-budget-of-expenditures-and-sources-of-financing) | Compare amounts by department, region, and year. |
| Population projections | [PSA — 2020 Census-Based Population Projections](https://psa.gov.ph/content/calabarzon-retain-top-spot-most-populous-region-until-2035) | Compare regional spending with projected population for the same year. |
| GRDP per capita | [PSA — GRDP tables](https://psa.gov.ph/statistics/grdp/tables) | Compare regional spending with economic output per person for the same year. |

Source files are staged in Google Drive before ingestion. File names and coverage are recorded in the [dataset documentation](profiling/README.md#dataset-index).

Match records by year and standard region code. Total the budget once per region-year before joining population or GRDP data. Use total population only, keep GRDP price bases separate, and exclude national totals, Central Office, and Nationwide from regional comparisons. Check historical boundary differences before comparing regions. Missing values stay missing.

These comparisons show patterns; they do not prove that spending caused an economic outcome.

## Start here

| Looking for… | Open |
|---|---|
| Source ingestion, setup, and operational checks | [Ingestion guide](docs/ingestion.md) |
| Dataset profiling, dictionaries, and findings | [Profiling index](profiling/README.md) |
| dbt connection setup and execution commands | [Databricks setup](dbt/README.md#databricks-first-run) · [Execution commands](dbt/README.md#day-to-day-commands) |
| Isolated-schema testing | [Test-first guide](dbt/TEST_FIRST.md) |
| Silver transformation documentation | [Completion rate](docs/silver/completion_rate.md) · [GRDP per capita](docs/silver/grdp_per_capita.md) · [Hospital](docs/silver/hospital.md) · [Population](docs/silver/population.md) · [Regional appropriations](docs/silver/regional_appropriations.md) |
| Current model and column definitions, including data tests | [Silver definitions and tests (YAML)](dbt/models/silver/schema.yml) · [Gold definitions and tests (YAML)](dbt/models/gold/schema.yml) |
| Current crosswalk mapping and validity logic | [Crosswalk guide](docs/shared_region_crosswalk.md) · [Crosswalk model (SQL)](dbt/models/silver/shared_region_crosswalk.sql) |
| SQL migration decisions and runtime safeguards | [Migration notes](dbt/MIGRATION.md) |
| Recorded offline validation | [Validation notes](dbt/VALIDATION.md) |
| Email alerts and failed-run recovery | [Pipeline failures and recovery](docs/ingestion.md#pipeline-failures-and-recovery) |

## Pipeline overview

| Stage | What happens | Implementation / default destination |
|---|---|---|
| Source preparation | Source reports are prepared as structured files. PDF/Excel extraction scripts used for preparation are not included in this repository. | Google Drive source files |
| Ingestion | Python discovers files, routes datasets, parses records, validates the load plan, and writes landing files and lineage. | `src/pondolens/` |
| Bronze | Source values and ingestion metadata are retained. | `pondolens.dev_bronze` |
| Profiling | SQL checks coverage, missing values, markers, duplicates, and proposed treatments. | `profiling/bronze/` |
| Silver | dbt standardizes types, labels, geography, and dataset-specific rules. | `pondolens.dev_silver` |
| Gold | dbt builds shared dimensions and facts at defined grains. | `pondolens.dev_gold` |
| Analysis and display | Gold tables support analytical queries and dashboard visuals. | [Analytics SQL](analytics/readme.md) and [dashboard export](dashboard/readme.md) |

Python ingestion and dbt transformations are separate tasks. **dbt requires Bronze data to exist first.** A new Databricks account also needs storage, authentication, permissions, and a configured connection; cloning this repository alone does not populate Bronze.

## Current repository status

As of **21 October 2026**:

| Component | Repository status |
|---|---|
| Google Drive ingestion | Modular Python implementation and Databricks runner are included. |
| Bronze profiling | Eleven dataset packages contain profiling SQL, a data dictionary, and findings. |
| dbt project | Configured project, source definitions, connection example, macros, selectors, and pinned dependencies are included. |
| Silver | Eleven executable dbt models are included. |
| Gold | Five dimension models and three fact models are included. |
| Data quality | dbt schema tests, custom SQL tests, in-model assertions, and separate DQ queries are included. |
| CI | Checks Python/notebooks, profiling packages, all ingestion unit tests, dbt materialization tests, and offline dbt parse/compile. Connected dbt builds run separately in Databricks. |
| Analytics and dashboard assets | SQL queries and a Databricks dashboard export are included. View setup limits are listed in the analytics guide. |
| Orchestration and monitoring | Databricks task setup is documented. No Prefect flow or central DQ results dashboard is implemented in this repository. |

The code inventory is separate from release acceptance. [Validation notes](dbt/VALIDATION.md) record offline checks; connected run evidence must identify the tested commit, runtime versions, schema variables, and results. A successful run of an earlier commit does not validate later changes.

## Datasets and models

Source families include DBM budget reports, PSA indicators, and hospital statistics from the source publication. Exact file references, units, and coverage are recorded in the dictionaries and findings linked from the [dataset documentation index](profiling/README.md#dataset-index).

| Bronze table | Silver model | Purpose |
|---|---|---|
| `regional_appropriation` | `regional_appropriations` | Regional appropriations from GAA files |
| `regional_obligations` | `regional_obligations` | Regional obligation records |
| `population` | `population` | Population projections by age group |
| `unemployment_rate` | `unemployment_rate` | Regional unemployment rates |
| `poverty_incidence` | `poverty_incidence` | Poverty incidence among families and population |
| `grdp_per_capita` | `grdp_per_capita` | Current-price and constant-2018-price measures |
| `completion_rate` | `completion_rate` | Completion percentages by education level and sex |
| `hospital` | `hospital` | Government regulated hospital counts |
| `region_boundaries` | `region_boundaries` | Geometry for choropleth maps |
| `service_access` | `service_access` | Retained access indicators used by the current Gold model |
| — | `shared_region_crosswalk` | Canonical region codes, names, aliases, and validity years |

`agency_actuals` remains an ingestion dataset and an optional dbt source, disabled by default through `include_agency_actuals`. It has no active Silver/Gold transformation. Service access remains in the executable dbt graph; removing it from the presentation does not disable that dependency. CHED graduates, standalone GRDP, and sector expenditure are excluded from the current ingestion configuration.

### Gold tables

| Table | One row represents |
|---|---|
| `dim_year` | One reference year |
| `dim_location` | One canonical location, with map geometry where available |
| `dim_age_group` | One age-group definition |
| `dim_particular` | One category and particular combination |
| `dim_indicator` | One indicator definition and unit |
| `fact_regional_expenditure` | One year × location × particular |
| `fact_regional_indicator` | One year × location × indicator |
| `fact_population` | One year × location × age group |

Facts connect through shared dimension keys. Aggregate each fact to the required comparison grain before combining results; joining raw facts on year and location can multiply rows. Model columns and relationship tests are defined in [Gold schema YAML](dbt/models/gold/schema.yml).

## Repository guide

| Path | Responsibility |
|---|---|
| `src/pondolens/ingestion/` | Drive access, routing, parsing, validation, and pipeline coordination |
| `src/pondolens/storage/` | Databricks storage, Delta writes, and ingestion logs |
| `src/pondolens/common/` | Configuration, dependencies, and fingerprints |
| `platform/databricks/runners/` | Databricks ingestion entry point |
| `dbt/models/bronze/` | Bronze source definitions |
| `dbt/models/silver/` | Silver transformations and schema documentation/tests |
| `dbt/models/gold/` | Gold dimensions, facts, and schema documentation/tests |
| `dbt/macros/` | Script materialization, schema routing, and reusable tests |
| `dbt/tests/` | Dataset and cross-model SQL checks |
| `dbt/verification/` | Offline materialization control-flow tests |
| `dbt/legacy_sql/` | Archived original scripts; outside active dbt model paths |
| `profiling/bronze/` | Profiling SQL, dictionaries, and findings |
| `docs/` | Ingestion, crosswalk, and selected Silver documentation |
| `data_quality/` | Additional DQ queries and notebooks |
| `analytics/`, `dashboard/` | Analytical queries, dashboard export, and setup guides |
| `tests/` | Ingestion unit tests and connected comparison script |
| `.github/workflows/ci.yml` | Automated repository checks |

## Run Bronze ingestion

Requirements: a Databricks checkout, Spark compute with Unity Catalog, storage permissions, a Google service account with source access, and its credentials stored in Databricks secrets. See the [ingestion guide](docs/ingestion.md) for exact parameters and setup.

1. Open [the ingestion runner](platform/databricks/runners/run_ingestion.py).
2. Review `catalog`, `schema`, `volume`, `drive_folder_id`, `secret_scope`, `secret_key`, `dataset`, `dry_run`, and `sheet_overrides_json`.
3. Start with `dataset=all` and `dry_run=true`; review the validated file plan.
4. Set `dry_run=false` to load the selected target.
5. Review the ingestion log for success, skipped datasets, or failures.

Dry runs do not create target storage or write data. Load runs create missing storage objects after preflight validation. Unchanged fingerprints and matching row counts produce skipped results.

Default landing volume: `/Volumes/pondolens/dev_bronze/government_budget`.

```sql
SELECT *
FROM pondolens.dev_bronze.gdrive_ingestion_log
ORDER BY finished_at DESC;
```

## Run dbt: Bronze to Silver to Gold

Configure a Databricks dbt task with project directory `dbt`, profile `pondolens`, a SQL warehouse, and the Run As identity's permissions. Use **one concurrent run and one dbt thread**. For external CLI execution, use [profiles.yml.example](dbt/profiles.yml.example) without committing credentials.

The dependency pins are in [requirements-dbt.txt](dbt/requirements-dbt.txt). Record the actual Core/adapter versions used in Databricks; a managed task may use a different version from those pins.

Start with isolated Silver/Gold destinations:

```sh
dbt parse
dbt build --threads 1 --vars '{"silver_schema":"dbt_test_silver","gold_schema":"dbt_test_gold"}'
```

These commands run from the dbt project directory. They read existing Bronze tables and write the selected Silver/Gold schemas. Repeat the build with unchanged inputs and compare IDs, row counts, and write metrics.

After acceptance, the development destinations use:

```sh
dbt build --threads 1
dbt docs generate
```

Default variables are `pondolens_catalog=pondolens`, `bronze_schema=dev_bronze`, `silver_schema=dev_silver`, and `gold_schema=dev_gold`. Git branch names do not change database destinations; use explicit variables for another environment.

`dbt build` runs models and tests in dependency order. `dbt test` checks existing tables without rebuilding them. Active models use a custom script materialization to execute SQL statements and assertions in order; this is documented in [MIGRATION.md](dbt/MIGRATION.md).

Keep Bronze stable during a build and avoid simultaneous notebook writers. Full refresh is blocked. Statements are not one transaction, so earlier writes may remain if a later check fails. The expenditure model no longer creates or reads the legacy backup table; retired particular `30051` rows require a separate migration before its MERGE can proceed.

## Local checks

Use Python **3.12** to match CI. From the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m pip install 'nbformat>=5.10,<6'
python -m pip install -r profiling/requirements-checks.txt
python scripts/check_code.py
python scripts/check_profiling.py
python -m pytest -q tests/unit
```

For dbt dependencies and offline materialization checks:

```sh
python -m pip install -r dbt/requirements-dbt.txt
python -m pytest -q dbt/verification
```

Offline checks do not execute transformations against Databricks. The [ingestion comparison script](tests/integration/validate_ingestion.py) requires a connected workspace; review its target schemas first. A local storage backend is not implemented.

## Data quality and limitations

- Completion rate has numeric observations for 2021–2024; the profiled 2025 column contains only missing markers. NIR is missing in 2021–2023.
- Hospital coverage is Government hospitals only, 2021–2024, across 17 source regions. It does not separately report NIR or measure beds, staffing, or care quality.
- Canonical aliases do not make historical regional boundaries comparable. Keep dataset-specific historical exceptions separate from shared crosswalk validity.
- Percentages and per-capita measures are not additive. Do not sum rates or average regional rates without appropriate denominators.
- Current Silver population keeps Both-sex age-group detail and excludes Total rows. Sum the non-overlapping age groups once per region-year.
- Missing values and source markers must not be interpreted as zero. Preserve status and reliability information when displaying indicators.
- A current boundary snapshot supports mapping but does not establish historical boundary consistency.
- Zero rescued rows and successful tests do not establish source accuracy or causal relationships.

## Team workflow and release

1. Start a task branch from the latest `dev`.
2. Keep code, documentation, and relevant validation evidence together.
3. Open a PR to `dev` and review checks and conflicts before merging.
4. Before promoting `dev` to `main`, validate the latest commit, record connected build/rerun results, and confirm the intended runtime configuration.
5. Treat a Git merge and a Databricks deployment as separate actions. Pulling code does not run ingestion or dbt.

Keep credentials outside Git. Use Databricks secrets or the configured task identity. Delete task branches only after confirming that their work is merged.

## Team

- [Rhea Mae Alum](https://www.linkedin.com/in/rhea-alum/)
- [Razzelle Ann Boreros](https://www.linkedin.com/in/razzelle-ann/)
- [Anjelika Marquez](https://www.linkedin.com/in/anjelika-m-a5868827b/)
- [Mia Barroga](https://www.linkedin.com/in/mia-barroga-ie/)
- [Christine Joy Balansay](https://www.linkedin.com/in/christine-joy-balansay-cfmp-b132b5277/)
