# PondoLens dbt — Bronze to Silver to Gold

This project executes the transformations supplied in your folder, documents the tables and runs data tests. Bronze ingestion stays in the Python pipeline. Existing notebook SQL is archived under `legacy_sql/`; active dbt models are under `models/`.

## Databricks first run

1. Extract this folder into the repository's `dbt/` directory. Use a branch and keep your current tables intact.
2. Create a Databricks dbt task, choose the SQL warehouse, and set the project directory to `dbt`. Use the Run As identity's authentication. The identity needs USE CATALOG, USE SCHEMA, SELECT on Bronze, and permission to create/modify tables in the target schemas. Pin `dbt-databricks==1.10.15`. Use one concurrent task/run and one dbt thread.
3. Match the task profile to `pondolens`. `profiles.yml.example` is available for external CLI use; no secrets are included. Connection host/path and authentication are workspace-specific and must be selected in the task.
4. Remove default seed/run commands. First use:

```sh
dbt parse
dbt build --threads 1 --vars '{"silver_schema":"dbt_test_silver","gold_schema":"dbt_test_gold"}'
```

This reads the existing `pondolens.dev_bronze` tables and creates isolated Silver/Gold test schemas. No Bronze ingestion is performed. Use an identity allowed to create the schemas.

5. Review failures, `target/run_results.json` and the warehouse query history. When the isolated build passes, the existing development destinations use:

```sh
dbt build --threads 1
dbt docs generate
```

Defaults are pondolens / dev_bronze / dev_silver / dev_gold. Override `pondolens_catalog`, `bronze_schema`, `silver_schema`, `gold_schema` for another environment. New accounts need Bronze data and connection permissions first.

## Day-to-day commands

```sh
dbt build --threads 1
dbt test --select hospital
dbt docs generate
```

Use `dbt build`, which runs models and tests in dependency order. `dbt test` alone checks existing tables. Do not use `--full-refresh`; the migration materialization blocks it to protect ID allocation. A failed parent blocks downstream build nodes. Keep Bronze stable during the run. Do not run a notebook writer at the same time.

## What is included

- 11 Silver models, including the crosswalk and service access.
- 8 Gold models: 5 dimensions and 3 facts, matching the supplied schema.
- Bronze source definitions, model/column documentation, required-field/unique/grain/FK tests and targeted data checks.
- A custom script materialization that preserves SQL validations and MERGE logic rather than silently rewriting business rules.
- Original files, migration decisions, pinned dependencies and offline verification notes.

Read `MIGRATION.md` for inherited behavior and runtime limits. Rate and per-capita indicators are not additive; the current population model excludes Total rows; sum non-overlapping age groups for a regional total. Source dates, units, historical boundaries and marker interpretation still need domain review. dbt cannot infer publication status absent from Silver.

## Acceptance

Offline parse and structural checks do not prove that queries run on your warehouse or that source values are correct. Run the isolated build and an immediate rerun; unchanged sources should not allocate new Silver/fact MERGE IDs. Gold year/location/age-group and population IDs now use stable natural-key MERGE. Record the dbt version, warehouse, schema variables and run artifacts. Only then promote the run configuration.
