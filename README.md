![PondoLens — Philippine Government Budget Analysis](docs/images/Philippine%20service%20banner%20with%20woven%20header.png)
PondoLens is an end-to-end data engineering capstone from the **FTW Foundation Data Engineering Scholarship Program, Batch 12**. It brings Philippine government budgets, population projections, and regional indicators into Databricks for analysis.

The main reporting scope is **2021–2025**. Coverage varies by dataset.

[Quick start](#quick-start) · [Documentation](#documentation) · [Silver guides](#silver-documentation) · [Dashboard](dashboard/PondoLens_Dashboard.md) · [Team](#team)

## What we explore

- **AP 1:** Where does the money go across departments and regions?
- **AP 2:** How does regional government spending compare to population?
- **AP 3:** How does regional government spending compare with GRDP per capita?

Allocation uses **appropriations**. Spending comparisons use **obligations**, which are recorded commitments rather than cash payments.

## Pipeline

Prepared source files in Google Drive → Python ingestion → Bronze → dbt Silver → Gold → dashboard.

**Stack:** Python, SQL, Google Drive API, Databricks, Delta Lake, dbt, and GitHub Actions.

Bronze retains source records and lineage. Silver standardizes values and geography. Gold provides **five dimensions and three facts**, connected by shared keys. See the [data model](docs/data_model.md).

| Data | Source |
|---|---|
| Government budgets and obligations | [DBM BESF](https://www.dbm.gov.ph/index.php/test/1205-budget-of-expenditures-and-sources-of-financing) |
| Population projections | [PSA population projections](https://psa.gov.ph/content/calabarzon-retain-top-spot-most-populous-region-until-2035) |
| GRDP per capita | [PSA GRDP tables](https://psa.gov.ph/statistics/grdp/tables) |

More datasets, source references, and coverage: [profiling index](profiling/README.md#dataset-index).

## Quick start

1. Configure Databricks storage, permissions, and Google Drive credentials using the [ingestion guide](docs/ingestion.md).
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

## Documentation

| Need | Open |
|---|---|
| Ingestion setup, credentials, email alerts, and recovery | [Ingestion guide](docs/ingestion.md) |
| Source profiling, dictionaries, and findings | [Profiling index](profiling/README.md) |
| dbt setup and daily commands | [dbt guide](dbt/README.md) |
| Isolated testing and build evidence | [Test-first guide](dbt/TEST_FIRST.md) · [Validation notes](dbt/VALIDATION.md) |
| Gold tables and relationships | [Data model](docs/data_model.md) |
| Column definitions and automated data tests | [Silver YAML](dbt/models/silver/schema.yml) · [Gold YAML](dbt/models/gold/schema.yml) |
| Analytics queries and dashboard setup | [Analytics](analytics/readme.md) · [Dashboard](dashboard/PondoLens_Dashboard.md) |
| Additional data-quality checks | [Data quality](data_quality/readme.md) |
| SQL migration and execution safeguards | [Migration notes](dbt/MIGRATION.md) |

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
