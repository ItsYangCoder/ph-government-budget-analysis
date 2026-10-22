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

## Silver health metrics

A full `dbt build` also creates `dq_silver_health` in the same monitoring schema after all 11 Silver models succeed. Pull the current code and run the build command above; no table reset is needed. Use [silver_health.sql](../analytics/data_quality/silver_health.sql) as the dashboard dataset.

This live view reads the current Silver rows when queried. `assessed_at` is the query time, not the last successful pipeline time. Keep the recorded build status and ingestion freshness visible alongside it; an existing view can still return results after a later failed build. Partial selections do not recreate the view.

| Metric | What the percentage means |
|---|---|
| Required identity completeness | Rows with every business-key field and region name populated. The crosswalk also requires its source alias. This does not assess every optional column. |
| Business-key uniqueness | Distinct typed keys / rows with complete keys. Missing keys are excluded and shown separately. Crosswalk alias uniqueness stays **Not assessed**. |
| Measurement availability | Reported primary measurements / stored rows. Zero counts as present. Confirmed source markers stay separate; unknown or contradictory statuses are unclassified. |
| Primary value validity | Reported primary values within the Silver rule: percentages 0–100, counts/budget amounts nonnegative, GRDP per capita positive. This does not validate every supporting measure or prove source accuracy. |
| Canonical code membership | Rows whose nonblank region code exists in the crosswalk. Budget-only Nationwide (`NW`) mappings are excluded from this denominator and assessed under year mapping. Alias duplicates cannot multiply the count. |
| Year mapping applicability | Rows with a year-valid code, the exact historical NIR treatment, or the budget-only Nationwide mapping used by Silver. Other windows need review; missing completion placeholders outside a validity window are excluded. |
| Expected key coverage | Expected distinct keys found / independently defined expected keys. A missing measurement placeholder can satisfy key coverage while reducing measurement availability. |
| Boundary presence / geometry structure | Expected regional codes with nonblank geometry, plus a separate typed Polygon/MultiPolygon array check. These do not prove topology, CRS, ring validity, or map accuracy. |
| Crosswalk interval validity | Ordered validity endpoints; NULL endpoints follow the existing unbounded mapping rule. |

The coverage reference follows the current source/model scope, rather than deriving expectations from rows that happen to exist:

| Dataset | Expected keys in the current release |
|---|---|
| Completion rate | 855: 2021–2025 × 18 regions plus Philippines × 3 education levels × 3 sex groups. |
| GRDP per capita | 185: 18 regions × 5 years × current/constant prices, plus 5 national current-price rows. |
| Hospital | 68: 17 regions excluding NIR × 2021–2024 × Government. |
| Population | 1,530: 17 regions excluding NIR × 2021–2025 × 18 age groups × Both sexes. |
| Poverty incidence | 108: 18 regions × 2021/2023/2025 × families/population indicators. |
| Region boundaries | 18 regional codes in the supplied boundary snapshot; CO, NW and PHL do not require polygons. |
| Unemployment rate | 87: 17 regions in 2021–2023 and 18 in 2024–2025. |
| Service access | 102: 17 regions excluding NIR × 2022/2024 × 3 APIS measures, with their source family denominators. |
| Regional appropriations, regional obligations, crosswalk aliases | **Not assessed** for expected key coverage until an independent detail/alias reference is established. |

Update the coverage contract when accepting new source releases. These are expected keys, not fixed health scores. Every percentage is calculated from actual rows. The view shows numerator, denominator, excluded and unresolved rows, invalid rows, missing expected keys, source-unavailable rows, and historical exceptions. A metric can legitimately be 100%; an empty eligible population returns NULL, not a passing score. Missing expected keys are separate from invalid stored records.

The two budget models explicitly map Nationwide to `NW` outside the shared crosswalk; this is an approved dataset exception in the 2021–2025 scope, not an unknown code. For historical NIR mapping, poverty requires `region_mapping_source='poverty_override'` in 2021/2023; GRDP permits 2021–2023 as validated by its Silver transformation. This view does not independently verify the workbook provenance or harmonize historical boundaries. Completion dot markers and obligations dash/blank statuses are treated as source-unavailable; unknown statuses, including unclassified completion blanks, remain visible for review.

For charts, compare datasets **within the same metric**, show numerator/denominator, and keep **Configured check results** separate. Do not average metric percentages or test pass rates into an overall health score. Missing rows, source limitations, and unassessed rules must remain visible. This view measures defined Silver rules; it is not a claim that all data is accurate or complete.

[data_quality_checks.dbquery.ipynb](data_quality_checks.dbquery.ipynb) remains a manual SQL notebook. Review its target tables before running it.

Record the tested commit, source snapshot, target schemas, run URL, and results in the validation record. Passing syntax checks alone does not confirm data correctness.
