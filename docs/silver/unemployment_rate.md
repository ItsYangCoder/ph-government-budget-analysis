# Unemployment Rate — Silver Pipeline

## Purpose
Transforms `pondolens.dev_bronze.unemployment_rate` into `pondolens.dev_silver.unemployment_rate` using the shared region crosswalk and an incremental Delta `MERGE`.

## Prerequisites
- Databricks SQL / Delta Lake, access to Bronze, Silver, and `pondolens.dev_silver.shared_region_crosswalk`.
- The crosswalk must contain `source_region_name`, `region_code`, `region_name`, with unique normalized aliases. Add all Bronze regional aliases there **before** running the script; do not silently infer region codes.
- Execute all statements sequentially in **one SQL session** and allow **one writer**. Source data should be stable for the duration of the run.
- The source is expected to contain `year`, `region`, `geographic_name`, `value`, `estimate_status`, `table_version`, `geographic_level`, and `indicator`.

## Grain and schema
One row per **year × region_code**, for 2021–2025. Silver columns: `unemployment_rate_id`, `year`, `region_code`, `region_name`, `unemployment_rate`, `run_id`, `source`, `processed_at`. IDs begin at 3,000,000 for an empty target; existing IDs are retained. Existing target IDs below 3,000,000 fail validation and require a planned migration before rerunning.

## Transformations
1. Restrict to region-level observations for the `unemployment rate` indicator.
2. Join region aliases to `shared_region_crosswalk` using `UPPER(TRIM(...))`, following `completion_rate.sql`.
3. Parse years and numeric percentages with `TRY_CAST`; enforce rates in `[0,100]`.
4. Apply the notebook's **project** release policy: 2021 any labeled release (unverified exception); 2022–2024 final; 2025 preliminary. The script rejects ambiguous selected releases with differing release identity/value. Identical duplicates are collapsed.
5. Merge by normalized `(year, region_code)`. Update changed rows, insert new keys, preserve IDs and unchanged timestamps. No automatic deletions.

## Validation and failure behavior
- Reject duplicate crosswalk aliases, unmapped regional rows, missing metadata, invalid years/rates, conflicting selected releases, duplicate target keys/IDs, and ID overflow.
- Pre-merge `assert_true` failures stop the SQL job before target changes. The final assertion verifies staged rates and region names against Silver.
- Out-of-scope records are ignored. Nonselected releases are excluded, not treated as errors; invalid in-scope records still block the run.
- The pipeline does **not** verify the authenticity of source releases. The 2021 exception and later-year release choices are project rules, not independent certification.

## Changes from notebook
- Replaced the hard-coded regional `CASE` mapping with the **shared crosswalk** used by `completion_rate.sql`.
- Removed manual mapping regression cases, diagnostic result sets, release registry creation, and snapshot-scope controls to keep the executable focused.
- Preserved the notebook's eight-column target, selected-release conflict safeguards, and stable-ID incremental upsert.
- **Important:** The notebook's explicit complete-snapshot missing-key checks are not implemented here. This SQL never deletes records missing from an incoming batch. If authoritative complete-snapshot reconciliation is required, implement a separate audited control before production deployment.

## Operational checks
Before a run, inspect crosswalk coverage and selected-release duplicates. After a run, inspect region counts per year and the Silver rows. Do not execute the MERGE independently after a failed assertion. This file was statically reviewed against the uploaded notebook and completion-rate script; it was **not executed in a Databricks workspace**.
