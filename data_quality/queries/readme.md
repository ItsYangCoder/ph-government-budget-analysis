# Manual data quality queries

| File | Purpose |
|---|---|
| [GRDP per capita report](grdp_per_capita_dq.sql) | Checks IDs, business keys, values, and mappings in Silver. |
| [Unemployment report](unemployment_rate_dq.dbquery.ipynb) | Reports Silver unemployment data quality results. |

Run these in Databricks after the target tables exist. Review the schema and column references first. These reports are separate from dbt and are not scheduled by CI.

For automated data checks, use the [dbt tests](../../dbt/tests/) and model schema tests. For raw-source checks, use the [profiling packages](../../profiling/README.md).
