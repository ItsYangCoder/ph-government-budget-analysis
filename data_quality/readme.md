# Data quality

Data checks run at several stages:

- Ingestion validates source files, replacement rules, and loaded row counts.
- [Bronze profiling](../profiling/README.md) checks source coverage, markers, and proposed treatments.
- dbt models run SQL assertions; [schema tests](../dbt/models/silver/schema.yml) and [custom tests](../dbt/tests/) check Silver and Gold data.
- [Additional queries](queries/readme.md) provide manual reports in Databricks.

Use `dbt build --threads 1` for transformations and tests in dependency order. CI runs offline checks; connected data checks run in Databricks.

[data_quality_checks.dbquery.ipynb](data_quality_checks.dbquery.ipynb) is a manual SQL notebook. Review its target tables before running it. This folder does not implement a central DQ results store or automated monitoring dashboard.

Record the tested commit, source snapshot, target schemas, run URL, and results in the validation record. Passing syntax checks alone does not confirm data correctness.
