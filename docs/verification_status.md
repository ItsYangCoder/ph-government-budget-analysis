## Databricks Bronze loading — October 6, 2026

Rhea reported the following results from running
`databricks/01_load_bronze.py` in Databricks:

| Check | Reported result |
|---|---|
| Uploaded extraction packages | 18 verified |
| Loaded Delta tables | 21 in `pondolens.bronze` |
| Total loaded records | 798,440 |
| Source Parquet versus loaded Delta | Row counts and record contents matched |
| Identical loading rerun | Zero candidate new rows |

Records include raw cells and extracted measures; they are not all
financial transactions.

These checks establish loading fidelity for the verified batch.
They do not resolve the source issues listed above or establish
analytical comparability.

## Separate Bronze helper verification — October 7, 2026

Rhea executed the updated helper code in
`databricks/verify_load_bronze_helper` using the `regional_2024` package
and its `regional_cells` table.

- Processing key: `5947eb19912048a9eeef6d3d0466e67d5ae3afac73ff41068d31f37726ddef7c`
- Target: `pondolens.bronze_test.helper_verification`
- First run: 840 source rows, 840 candidate new rows, `verified: True`.
- Identical rerun: zero candidate new rows, `verified: True`.

Verification covers this table and revision with a single writer.
Other packages and remote concurrency have not been verified through
this separate helper.

## Next milestone

Run read-only Bronze profiling and document findings with exact
source locations and representative examples.

Review years, units, reporting statuses, hierarchy, processing
revisions, and geographic compatibility before defining Silver rules.

Bronze profiling results and Silver readiness have not yet been verified.