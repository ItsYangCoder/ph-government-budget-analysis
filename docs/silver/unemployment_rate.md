# Unemployment Rate — Silver Pipeline

Documented by: **Anjelika Marquez**  
Model: [unemployment_rate.sql](../../dbt/models/silver/unemployment_rate.sql)

## Purpose
Transforms `pondolens.dev_bronze.unemployment_rate` into `pondolens.dev_silver.unemployment_rate` using the shared region crosswalk and an incremental Delta `MERGE`.

## Prerequisites
- Databricks SQL / Delta Lake, access to Bronze, Silver, and `pondolens.dev_silver.shared_region_crosswalk`.
- The crosswalk must contain `source_region`, `region_code`, `region_name`, `valid_from_year`, and `valid_to_year`. Equivalent aliases may repeat; conflicting region codes within overlapping validity windows block the load.
- Execute all statements sequentially in **one SQL session** and allow **one writer**. Source data should be stable for the duration of the run.
- The source is expected to contain `year`, `region`, `geographic_name`, `value`, `estimate_status`, `table_version`, `geographic_level`, and `indicator`.

## Grain and schema
One row per **year × region_code**, for 2021–2025. Silver columns: `unemployment_rate_id`, `year`, `region_code`, `region_name`, `unemployment_rate`, `run_id`, `source`, `processed_at`. IDs begin at 3,000,000 for an empty target; existing IDs are retained. Existing target IDs below 3,000,000 fail validation and require a planned migration before rerunning.

## Data dictionary

| Column | Type | Meaning |
|---|---|---|
| unemployment_rate_id | INT | Persistent ID starting at 3,000,000 for an empty target. |
| year | INT | Observation year, 2021–2025. |
| region_code | STRING | Canonical region code from the crosswalk. |
| region_name | STRING | Crosswalk region name stored in uppercase. |
| unemployment_rate | DECIMAL(12,4) | Unemployment percentage; 5 means 5%. |
| run_id | STRING | Run label recorded on insertion or a detected change. |
| source | STRING | Resolved Bronze table reference. |
| processed_at | TIMESTAMP | Insertion or last detected update time. |

Selected release status and table version are validated in staging but are not stored as dedicated Silver columns. Original release details remain in Bronze. Existing rows absent from a later source are retained; the model does not enforce complete year/region coverage.

## Transformations
1. Restrict to region-level observations for the `unemployment rate` indicator.
2. Normalize source and crosswalk aliases by uppercasing and removing punctuation and spaces. Join using year-valid crosswalk intervals.
3. Parse years and numeric percentages with `TRY_CAST`; enforce rates in `[0,100]`.
4. Apply the notebook's **project** release policy: 2021 any nonblank labeled release; 2022–2024 final; 2025 preliminary. The script rejects ambiguous selected releases with differing release identity/value. Identical duplicates are collapsed.
5. Merge by normalized `(year, region_code)`. Update changed rows, insert new keys, preserve IDs and unchanged timestamps. No automatic deletions.

## Validation and failure behavior
- Reject conflicting overlapping crosswalk mappings, unmapped regional rows, missing metadata, invalid years/rates, conflicting selected releases, duplicate target keys/IDs, and ID overflow.
- Assertions stop execution on failure. Schema/table creation occurs before validation and can remain if a later assertion fails. The final assertion verifies staged rates and region names against Silver.
- Out-of-scope records are ignored. Nonselected releases are excluded, not treated as errors; invalid in-scope records still block the run.
- The pipeline does **not** verify the authenticity of source releases. The 2021 policy accepts the source Not specified label without interpreting it as Final. Later-year release choices are also project selection rules.

## Operational checks
Before a run, inspect crosswalk coverage and selected-release duplicates. After a run, inspect region counts per year and the Silver rows. Do not execute the MERGE independently after a failed assertion. Connected project builds are recorded in [validation notes](../../dbt/VALIDATION.md). Run through dbt with one thread and one concurrent writer; dbt resolves the configured source and destination schemas.

## Related files

- [Silver SQL](../../dbt/models/silver/unemployment_rate.sql)
- [Silver definitions and tests](../../dbt/models/silver/schema.yml)
- [Bronze findings](../../profiling/bronze/unemployment_rate/findings.md)
- [Bronze data dictionary](../../profiling/bronze/unemployment_rate/data_dictionary.md)
- [Crosswalk guide](../shared_region_crosswalk.md)
- [Pipeline recovery](../ingestion.md#pipeline-failures-and-recovery)
