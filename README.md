![PondoLens — Philippine Government Budget Analysis](docs/images/Philippine%20service%20banner%20with%20woven%20header.png)
PondoLens is an end-to-end data engineering capstone from the **FTW Foundation Data Engineering Scholarship Program, Batch 12**. It brings Philippine government budgets, population projections, and regional indicators into Databricks for analysis.

The main reporting scope is **2021–2025**. Coverage varies by dataset.

[Why Databricks](#why-databricks) · [Data process](#how-the-data-moves) · [Quick start](#quick-start) · [Documentation](#documentation) · [Silver guides](#silver-documentation) · [Dashboard](dashboard/PondoLens_Dashboard.md) · [Team](#team)

## What we explore

- **AP 1:** Where does the money go across departments and regions?
- **AP 2:** How does regional government spending compare to population?
- **AP 3:** How does regional government spending compare with GRDP per capita?

Allocation uses **appropriations**. Spending comparisons use **obligations**, which are recorded commitments rather than cash payments.

## Why Databricks?

Databricks is the shared workspace where we load, clean, store, and analyze the project data using Python and SQL. We chose it so the team can work with the same tables and run the pipeline in one environment.

For PondoLens, Delta Lake stores the tables and their change history, Unity Catalog organizes them under named schemas and controls access, and Databricks jobs run the ingestion and dbt tasks. SQL queries and dashboards turn the prepared data into charts.

**Stack:** Python, SQL, Google Drive API, Databricks, Delta Lake, dbt, and GitHub Actions.

## How the data moves

Data engineering turns source files into reliable tables that people can use for analysis. Our process is:

| Step | What happens in PondoLens |
|---|---|
| **1. Collect and load** | Prepared source files are stored in Google Drive. Python uses the Google Drive API to load them into Databricks. |
| **2. Bronze — retain the source** | Store source values and tracking details, including the file and ingestion run. This lets us trace records back to their input. |
| **3. Silver — clean and check** | dbt runs SQL to standardize types, region names, units, and dataset-specific rules. Checks block invalid records from loading. |
| **4. Gold — prepare for analysis** | dbt builds shared lookup tables (dimensions) and measurement tables (facts), connecting budgets, population, and indicators by year and location. |
| **5. Query and display** | Analytics SQL calculates the reporting measures. Databricks dashboards display the results as charts and maps. |

Python handles ingestion; dbt handles the Bronze-to-Silver-to-Gold transformations and data tests. Jobs run these tasks in order. GitHub stores the code and runs automated checks before changes are merged.

Gold contains **five dimensions and three facts**. See the [data model](docs/data_model.md) for their relationships.

## Data sources

| Data | Source |
|---|---|
| Government budgets and obligations | [DBM BESF](https://www.dbm.gov.ph/index.php/test/1205-budget-of-expenditures-and-sources-of-financing) |
| Population projections | [PSA population projections](https://psa.gov.ph/content/calabarzon-retain-top-spot-most-populous-region-until-2035) |
| GRDP per capita | [PSA GRDP tables](https://psa.gov.ph/statistics/grdp/tables) |

More datasets, source references, and coverage: [profiling index](profiling/README.md#dataset-index).

## Quick start

You can explore this project using **Databricks Free Edition**, a free account for learning and personal projects, subject to usage limits. [Create a free account](https://login.databricks.com/?dbx_source=docs&intent=CE_SIGN_UP) or [log in to Databricks](https://login.databricks.com/), then follow the setup below. See the [official Free Edition guide](https://docs.databricks.com/aws/en/getting-started/free-edition) for details.

1. Download the prepared data and configure your own Drive connection using [Set up your own Google Drive](#set-up-your-own-google-drive). Then configure Databricks storage and permissions using the [ingestion guide](docs/ingestion.md).
2. Run the [ingestion runner](platform/databricks/runners/run_ingestion.py) with `dry_run=true`, review the plan, then load Bronze with `dry_run=false`.
3. Configure the [Databricks dbt task](dbt/README.md#databricks-first-run). Bronze must exist before dbt runs.
4. From the `dbt` project directory, validate in isolated schemas:

```sh
dbt parse
dbt build --threads 1 --vars '{"silver_schema":"dbt_test_silver","gold_schema":"dbt_test_gold"}'
```

Repeat with unchanged inputs and compare IDs, row counts, and write metrics. After acceptance, run `dbt build --threads 1` for the default destinations.

Defaults: `pondolens.dev_bronze`, `pondolens.dev_silver`, and `pondolens.dev_gold`. Git branches do not change those destinations. Use one concurrent run and one dbt thread.

Full setup and commands: [dbt guide](dbt/README.md). Failed-run steps: [pipeline recovery](docs/ingestion.md#pipeline-failures-and-recovery).

### Set up your own Google Drive

Use your own Google Cloud project, service account, and Databricks credentials. The team's credentials are not included in this repository and are not required.

1. **Get the data:** open [PondoLens prepared datasets](https://drive.google.com/drive/folders/1L_kvzPjQE60GjUvthLuwxbC3xKevHsoB), download the folder contents, extract them, and upload them into a folder in your own Google Drive. Preserve the subfolders, file names, and formats so dataset routing still works. These are the prepared ingestion inputs, not a download of the original government publications.
2. **Enable the API:** create a project in [Google Cloud Console](https://console.cloud.google.com/) and enable **Google Drive API** under APIs & Services → Library.
3. **Create credentials:** go to IAM & Admin → Service Accounts, create an account, then open Keys → Add key → Create new key → JSON. This pipeline uses a service-account JSON key, not an API key or interactive OAuth login. See [Google's credential guide](https://developers.google.com/workspace/guides/create-credentials#service-account-credentials).
4. **Grant access:** share your uploaded data folder with the service account's email address as **Viewer**. This allows the pipeline to read your copy.
5. **Connect Databricks:** store your JSON key in your own Databricks secret scope/key. Set the runner's `secret_scope` and `secret_key` to those names. Keep the JSON out of Git and notebook outputs. See [credential setup](docs/ingestion.md#set-up-your-own-drive-connection) for details and the supported private-file option.
6. **Use your folder ID:** copy the ID after `/folders/` in your Drive URL into `drive_folder_id`. Override the project default with your own ID, then run `dry_run=true` and review the file plan before loading.

Downloading the datasets does not grant access to the team's service account or Databricks workspace. Run against your own folder and workspace.

## Documentation

Click a guide below to open it in this repository. Each guide explains one part of the project and links to the related code.

**New to the project?** Read the Data model to understand the tables, then the Ingestion guide and dbt guide to follow how data is loaded and transformed. Use Analytics and Dashboard when you are ready to explore the results.

| Guide | What it explains | When to use it |
|---|---|---|
| [Ingestion guide](docs/ingestion.md) | How source files move from Google Drive into Bronze, including credentials, job settings, alerts, and recovery. | Set up the first load or troubleshoot a failed pipeline. |
| [Profiling index](profiling/README.md) | Checks on source coverage, missing values, duplicates, and findings. Each dataset includes a dictionary explaining its columns. | Understand the source data before cleaning or using it. |
| [dbt guide](dbt/README.md) | How to connect dbt to Databricks and run the Silver/Gold transformations and tests. | Configure the transformation task or run the pipeline after Bronze is loaded. |
| [Test-first guide](dbt/TEST_FIRST.md) | How to test using separate schemas, which are named groups of tables. | Try changes without writing to the default Silver/Gold tables. |
| [Validation notes](dbt/VALIDATION.md) | Recorded build results, tested versions, and the limits of the available evidence. | Review what has been checked and what still needs verification. |
| [Data model](docs/data_model.md) | What each Gold table represents and how table keys connect budgets, population, and indicators. | Plan a query or understand which tables to join. |
| [Silver YAML](dbt/models/silver/schema.yml) · [Gold YAML](dbt/models/gold/schema.yml) | dbt configuration files containing column descriptions and automated data tests. GitHub displays these as code. | Check column definitions or review the tests attached to a model. |
| [Analytics](analytics/readme.md) | SQL queries and setup steps for the three analytical questions. | Calculate the reporting measures after building Gold. |
| [Dashboard](dashboard/PondoLens_Dashboard.md) | Chart definitions, data sources, calculations, and setup for the Databricks dashboard export. | Set up the dashboard or trace a chart back to its data. |
| [Data quality](data_quality/readme.md) | Additional checks that complement the tests inside dbt. | Investigate values or run targeted dataset checks. |
| [Migration notes](dbt/MIGRATION.md) | How the original SQL was adapted into dbt and how the scripts execute. | Review transformation changes and execution safeguards. |

## Silver documentation

Guides cover columns, cleaning rules, checks, and load behavior.

| Dataset | Documentation | Model |
|---|---|---|
| Completion rate | [Guide](docs/silver/completion_rate.md) | [SQL](dbt/models/silver/completion_rate.sql) |
| GRDP per capita | [Guide](docs/silver/grdp_per_capita.md) | [SQL](dbt/models/silver/grdp_per_capita.sql) |
| Hospital | [Guide](docs/silver/hospital.md) | [SQL](dbt/models/silver/hospital.sql) |
| Population | [Guide](docs/silver/population.md) | [SQL](dbt/models/silver/population.sql) |
| Poverty incidence | [Guide](docs/silver/poverty_incidence.md) | [SQL](dbt/models/silver/poverty_incidence.sql) |
| Region boundaries / choropleth geometry | [Guide](docs/silver/region_boundaries.md) | [SQL](dbt/models/silver/region_boundaries.sql) |
| Regional appropriations | [Guide](docs/silver/regional_appropriations.md) | [SQL](dbt/models/silver/regional_appropriations.sql) |
| Regional obligations | [Guide](docs/silver/regional_obligations.md) | [SQL](dbt/models/silver/regional_obligations.sql) |
| Service access | [Guide](docs/silver/service_access.md) | [SQL](dbt/models/silver/service_access.sql) |
| Unemployment rate | [Guide](docs/silver/unemployment_rate.md) | [SQL](dbt/models/silver/unemployment_rate.sql) |
| Shared region crosswalk | [Guide](docs/shared_region_crosswalk.md) | [SQL](dbt/models/silver/shared_region_crosswalk.sql) |

Column definitions and data tests: [Silver schema YAML](dbt/models/silver/schema.yml).

## Repository map

| Folder | Contains |
|---|---|
| `src/pondolens/` | Python ingestion, validation, configuration, and storage |
| `platform/databricks/` | Databricks ingestion runner |
| `dbt/` | Bronze sources, Silver/Gold models, macros, and tests |
| `profiling/` | Dataset profiling SQL, dictionaries, and findings |
| `docs/` | Operational guides, Silver documentation, and data model |
| `analytics/`, `dashboard/` | Analysis queries and dashboard assets |
| `tests/`, `.github/workflows/` | Ingestion tests and CI checks |

## Quality and interpretation

CI runs code checks, profiling checks, ingestion unit tests, and offline dbt validation. Connected builds and rerun checks run separately in Databricks; see [validation notes](dbt/VALIDATION.md).

Compare datasets at the same year and region grain. Aggregate each fact before joining to avoid repeated amounts. Sum non-overlapping population age groups once; keep GRDP price bases separate. Percentages and per-capita values are not additive.

Coverage and missing-value treatments differ by dataset. Check the relevant Silver guide and preserve status fields. Regional codes do not establish historical boundary compatibility, and spending comparisons do not prove causation.

## Team

- [Rhea Mae Alum](https://www.linkedin.com/in/rhea-alum/)
- [Razzelle Ann Boreros](https://www.linkedin.com/in/razzelle-ann/)
- [Anjelika Marquez](https://www.linkedin.com/in/anjelika-m-a5868827b/)
- [Mia Barroga](https://www.linkedin.com/in/mia-barroga-ie/)
- [Christine Joy Balansay](https://www.linkedin.com/in/christine-joy-balansay-cfmp-b132b5277/)
