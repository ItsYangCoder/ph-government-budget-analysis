# Validation record

## Connected Databricks builds

The supplied build logs record two successful builds against `pondolens.dbt_test_silver` and `pondolens.dbt_test_gold`, using one thread, dbt Core **1.12.5**, and dbt-databricks **1.12.7**.

| Build | Successful models | Passed data tests | Warnings / errors / skipped | Duration |
|---|---:|---:|---|---|
| First supplied build | 19 | 235 | 0 / 0 / 0 | 494.70 seconds |
| Second supplied build | 19 | 235 | 0 / 0 / 0 | 578.70 seconds |

Commands ran from the dbt project directory:

```sh
dbt parse
dbt build --threads 1 --vars '{"silver_schema":"dbt_test_silver","gold_schema":"dbt_test_gold"}'
```

The downloaded second-run artifact was readable. Its `target/run_results.json` confirms 19 success and 235 pass results, with:

- Generated at: 21 October 2026, 4:04:51 PM Asia/Manila (`2026-10-21T08:04:51.345059Z`).
- Invocation ID: `abf7fa0f-90a0-4794-be2d-6d225cfab4cb`.
- Databricks job ID: `973274883707641`.
- Job run ID reported by adapter results: `5662545503857`.
- Task run ID reported by adapter results: `466222272092185`.

Evidence reviewed: the two supplied build logs and `dbt-output.tar.gz`. Raw driver logs, signed artifact URLs, and credentials are not stored in Git.

These results establish successful dbt model execution and tests for the supplied runs. The tested Git commit and run URLs were not captured in the supplied evidence. They do not certify every later revision or independently prove stable IDs, unchanged timestamps, source completeness, or dashboard query results.

Driver logs also contained dbt wrapper and artifact-upload errors. Those are separate from the successful dbt results; the final Databricks job state and email-alert delivery still need their own confirmation. A readable downloaded artifact does not prove every wrapper step succeeded.

## Offline checks

The original offline verification used dbt Core and adapter **1.10.15**:

- `dbt parse`: passed.
- `dbt compile --no-introspect --no-populate-cache --threads 1`: passed for 19 models and 235 data tests using isolated Silver/Gold schema variables.
- Three materialization control-flow tests passed: statement order/result fetching, stop-on-failure, and full-refresh rejection.
- The initial migration compared 19 original files with the supplied ZIP; 18 remain after removal of an obsolete archived script.

CI performs offline checks without a warehouse connection. It does not replace the connected build.

## Evidence to retain for each release

Record the Git commit, run URL, Core/adapter versions, target schemas, model/test totals, and overall job status. For unchanged reruns, compare target IDs, row counts, timestamps, and write metrics. Run analytics setup and dashboard previews separately because analytics SQL is outside the dbt graph.

See [test-first execution](TEST_FIRST.md) and [pipeline recovery](../docs/ingestion.md#pipeline-failures-and-recovery).
