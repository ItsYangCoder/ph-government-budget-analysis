# First run — Databricks

Project directory: the extracted `dbt` folder.
SQL warehouse: select your existing warehouse.
Warehouse catalog: `pondolens`.
Warehouse schema: `dbt_test_silver`.
Adapter: `dbt-databricks==1.10.15`.
Maximum concurrent runs: `1`.

Use these two commands in the dbt task:

```sh
dbt parse
dbt build --threads 1 --vars '{"silver_schema":"dbt_test_silver","gold_schema":"dbt_test_gold"}'
```

Bronze stays in dev_bronze. The build creates the two test schemas when permissions allow. After a successful build, run the same build command again and review ID stability and test results. Keep target/run_results.json and the warehouse query history. Do not run the archived notebooks alongside this task.

A connection or permission error requires configuring the warehouse/Run As identity. A failed SQL assertion requires reviewing the reported source or existing target condition; do not bypass it. The offline checks do not establish that source data satisfies those assertions.
