-- DQ dashboard datasets. Run each SELECT separately.
-- Change prod_monitoring if the build uses another monitoring schema.

-- Run history and headline status. Filter command='build' for full build reporting.
SELECT *
FROM pondolens.prod_monitoring.dq_run_summary
ORDER BY run_started_at DESC;

-- Dataset table: use layer to filter Silver, Bronze, or Gold.
SELECT *
FROM pondolens.prod_monitoring.dq_dataset_summary
ORDER BY layer, dataset;

-- Latest recorded build problems. An empty result is not proof that a run happened;
-- always show the latest run timestamp and run_status alongside this list.
WITH latest_build AS (
  SELECT invocation_id
  FROM pondolens.prod_monitoring.dq_run_summary
  WHERE command = 'build'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY bronze_schema, silver_schema, gold_schema
    ORDER BY run_started_at DESC, invocation_id DESC
  ) = 1
)
SELECT r.invocation_id, r.check_name, r.resource_type,
       r.status, r.failures, r.datasets, r.execution_seconds, r.run_started_at
FROM pondolens.prod_monitoring.dq_results r
JOIN latest_build b ON r.invocation_id = b.invocation_id
WHERE r.status NOT IN ('pass', 'success')
ORDER BY r.run_started_at DESC, r.status, r.check_name;
