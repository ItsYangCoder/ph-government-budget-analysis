# Pipeline alerts and recovery

Applies to Python Bronze ingestion and dbt Silver/Gold jobs. The job owner handles the first review; involve the dataset owner for source or mapping issues.

**Alert status:** setup and email delivery have not yet been verified. This guide does not configure a Databricks job. Record the job link, recipient, and successful alert test after setup.

## Set up failure emails

Use the existing jobs. If ingestion and dbt run as separate jobs, configure both.

1. Open the job in **Jobs & Pipelines**.
2. In job details, open **Job notifications → Edit notifications → Add notification**.
3. Choose **Email address**, enter the agreed recipient, select **Failure**, and save.
4. To catch a task failure even when the overall job finishes as “Succeeded with failures,” also configure **Failure** notifications on the ingestion and dbt tasks.
5. Review the actual retry policy. Use **Mute notifications until the last retry** for task alerts if the team only wants final-attempt failures. Job-level failure emails do not report each intermediate retry.

You need job owner or CAN MANAGE permission. Do not add SMTP code or email passwords to the pipeline. Avoid duplicate job/task alerts unless both are needed.

Notifications follow job/task state. An ERROR line in driver logs does not automatically trigger a failure email when the task succeeds. GitHub CI notifications are separate from Databricks job alerts.

### Test delivery safely

Create a temporary, unscheduled test job with the same recipient settings and one Python notebook task containing:

```python
raise RuntimeError("PondoLens failure alert test — no data writes")
```

Confirm that the task fails and the email arrives. Check spam if needed. Record the test run URL, recipient, and receipt time, then remove the temporary test job. This verifies the notification path; also check that each real job has saved recipient settings. Do not break source data or change a live dbt command to test delivery.

## When a run fails

1. **Pause scheduled runs and downstream refreshes.** Tell the team which data may be incomplete. Keep one writer only.
2. **Save evidence before retrying:** job/task run URLs, final state, first failed task/model/statement, error message, Git commit, Core/adapter versions, target variables, and source run IDs/hashes.
3. **Check what already changed.** Ingestion commits per table. dbt scripts commit statements separately. A failed run can leave some tables updated; it is not an automatic rollback.
4. **Fix the cause**, then choose rerun or recovery below. Do not bypass assertions, reset IDs, or use `--full-refresh`.

Keep raw logs and artifacts in a restricted evidence location. Do not commit tokens, service-account JSON, or signed download URLs.

### Inspect the affected tables

Use the actual catalog/schema from the failed run. These examples inspect the isolated test target; do not substitute a shared target without checking it first.

```sql
DESCRIBE HISTORY pondolens.dbt_test_silver.hospital LIMIT 10;
DESCRIBE HISTORY pondolens.dbt_test_gold.fact_regional_expenditure LIMIT 10;
```

Match history timestamps and job/run details to the failed attempt. Save the relevant versions and operation metrics. A newer table version alone does not mean rows changed.

For ingestion, inspect the configured Bronze log:

```sql
SELECT run_id, dataset, status, rows_loaded, message, started_at, finished_at
FROM pondolens.dev_bronze.gdrive_ingestion_log
ORDER BY finished_at DESC;
```

Preflight failures may occur before an audit row exists; check the task logs too.

## Choose the recovery action

| Failure | Action |
|---|---|
| Authentication, permissions, warehouse, or connection | Fix access/compute first. Confirm no other writer is active, then rerun the same validated configuration. |
| Missing files, invalid values, mapping conflict, or SQL assertion | Review the reported records with the dataset owner. Restore a complete source or correct the mapping/code. Do not convert unknown values to zero or disable checks to force a pass. |
| Ingestion fails after some tables load | Review each dataset’s status and table history. Fix the cause, rerun dry-run validation against the complete source, then reload with the same target. Verify skipped datasets rather than assuming they are correct. |
| dbt fails after some writes | Inspect affected tables and source completeness. With valid unchanged inputs and code, rerun the full build so downstream models and tests run again. Do not resume at an arbitrary SQL statement. |
| Bad data was committed | Keep refreshes paused. Identify a known-good source and table-version set, review affected downstream tables and ID links, then agree a coordinated recovery before writing. |
| dbt passes but wrapper/artifact handling reports errors | Check the final task/job state and whether artifacts can be downloaded. Record the build result separately from the wrapper issue. Investigate task/runtime setup; do not change model SQL just to silence driver messages. |

**Completeness matters:** current ingestion checks missing files/columns but does not fully detect a truncated replacement of the same file. Some models can delete rows during snapshot synchronization. Check year, region, age-group coverage, and row counts before rerunning a partial source.

### If table restoration is needed

Use Delta history/time travel to compare the current and known-good versions first. Have the job owner and dataset owner review the exact versions and affected tables. Restoring a table can discard valid later changes and break dimension/fact links if related tables are left at incompatible versions.

Restore only the agreed table set, then rebuild and test dependent models. Do not drop/recreate tables or reset surrogate IDs. Do not run VACUUM while recovery is being assessed. Historical data files must still exist; table history is not a long-term backup.

No restoration commands are run by this guide. Record every approved recovery action and its resulting table versions.

## Validate before resuming

Run the same tested code and target variables after the cause is fixed. For the isolated target:

```sh
dbt build --threads 1 --vars '{"silver_schema":"dbt_test_silver","gold_schema":"dbt_test_gold"}'
```

For another environment, use the failed run’s verified variables. Do not accidentally rerun with defaults against a different schema.

- All required models/tests finish successfully; investigate skipped or warned results.
- Row counts, region/year coverage, and totals agree with the complete source.
- Existing business keys keep their IDs; no duplicate IDs or broken relationships appear.
- Review MERGE insert/update/delete metrics. An unchanged rerun should not change business values or allocate new IDs. Some models may still update metadata, so check model behavior rather than requiring every write metric to be zero.
- Recreate/check analytics views separately; they are not part of the dbt graph.
- Resume schedules and dashboard refreshes only after the job owner confirms these checks.

## Incident record

Record: owner, incident time, job/task run links, tested commit, source snapshot, target schemas, first error, affected tables and versions, cause, fix, rerun links, validation results, and time refreshes resumed. Track unresolved follow-ups separately.

## References

- [Databricks job notifications](https://docs.databricks.com/aws/en/jobs/notifications)
- [Delta table history and time travel](https://docs.databricks.com/aws/en/tables/history)
- [Ingestion guide](ingestion.md)
- [dbt execution and safeguards](../dbt/README.md)
- [Validation record](../dbt/VALIDATION.md)
