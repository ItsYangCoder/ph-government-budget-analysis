# Data quality

Data checks run at several stages:

- Ingestion validates source files, replacement rules, and loaded row counts.
- [Bronze profiling](../profiling/README.md) checks source coverage, markers, and proposed treatments.
- dbt models run SQL assertions; [schema tests](../dbt/models/silver/schema.yml) and [custom tests](../dbt/tests/) check Silver and Gold data.
- [Additional queries](queries/readme.md) provide manual reports in Databricks.

Use `dbt build --threads 1` for transformations and tests in dependency order. CI runs offline checks; connected data checks run in Databricks.

## DQ history and dashboard queries

After `dbt build`, an on-run-end hook saves model and test outcomes into a separate monitoring schema. With `gold_schema=prod_gold`, the default is `pondolens.prod_monitoring`; `dev_gold` uses `dev_monitoring`, and `dbt_test_gold` uses `dbt_test_monitoring`. Override with `monitoring_schema` if needed. Parse/compile commands do not write monitoring data.

| Object | Use |
|---|---|
| `dq_results` — Delta table | History of model/test outcomes by invocation and node, with status, failing-row count when available, duration, related datasets, target schemas, and run timestamps. |
| `dq_run_summary` — view | Run totals and PASS, WARN, FAIL, INCOMPLETE, PARTIAL_COMMAND, or PARTIAL_SELECTION status. |
| `dq_latest_status` — view | Latest build outcome per node and target combination. Its rows can belong to different invocations; use run summary for whole-build status. |
| `dq_dataset_summary` — view | Dataset results from the latest recorded build for each target combination, grouped by Bronze/Silver/Gold. |

Use [dashboard queries](../analytics/data_quality/monitoring.sql) to create run-status counters, a dataset-status table, a failure list, and a run-history chart. These are ready-to-use SQL queries; this change does not publish a dashboard. The analytical budget dashboard still reads Gold facts and dimensions.

Run the same build command as before. For an explicit destination:

```sh
dbt build --threads 1 --vars '{"silver_schema":"prod_silver","gold_schema":"prod_gold","monitoring_schema":"prod_monitoring"}'
```

The job identity needs permission to create/use the monitoring schema and create/modify its table and views. Keep one concurrent writer. To disable recording explicitly, pass `enable_dq_monitoring: false` in the vars; monitoring is enabled by default.

Results start with the next build; earlier logs are not backfilled. Each invocation gets its own history, and replaying a node within the same invocation does not duplicate it. The hook records both successful and failed node outcomes when dbt reaches the hook; it does not turn failed tests into passes. A monitoring write error fails the hook and requires investigation.

**Limits:** cancellation, connection loss, parse errors, and fail-fast termination can prevent the end hook from running. A missing run is not a pass; use Databricks job status and failure notifications as well. A model's SQL assertions are represented by its model outcome, not separate test rows. Multi-dataset tests are attributed to each related dataset, so dataset test counts must not be added to calculate a global count. Partial selections are not labeled as a full-project PASS. Raw error messages and failing source rows are not stored; use job logs for details.

[data_quality_checks.dbquery.ipynb](data_quality_checks.dbquery.ipynb) remains a manual SQL notebook. Review its target tables before running it.

Record the tested commit, source snapshot, target schemas, run URL, and results in the validation record. Passing syntax checks alone does not confirm data correctness.
