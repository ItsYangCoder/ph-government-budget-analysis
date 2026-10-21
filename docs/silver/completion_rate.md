# Completion Rate — Silver Documentation

Assigned to: Rhea  
Updated: 19 October 2026 (Asia/Manila)  
Source: `pondolens.dev_bronze.completion_rate`  
Reference: `pondolens.dev_silver.shared_region_crosswalk`  
Target: `pondolens.dev_silver.completion_rate`  
SQL: `dbt/models/silver/completion_rate.sql`  
Scope: source year labels 2021–2025

## Purpose and grain

Standardize education completion percentages by year, location, education level, and sex.

One row represents **indicator × year × region_code × level_of_education × sex**. This combination is the natural key. `completion_rate_id` is the surrogate identifier.

Completion rates are percentages, not graduate headcounts. Interpret the denominator, reference period, and footnotes using the official source publication.

## Output data dictionary

| Column | Type | Description |
|---|---|---|
| completion_rate_id | BIGINT | Surrogate ID starting at 8,000,001; preserved for existing matched natural keys. |
| year | INT | Source year label; current transformation covers 2021–2025. |
| region_code | STRING | Standard project code from the crosswalk; PHL identifies Philippines. These are project codes, not official PSGC codes. |
| region_name | STRING | Standard name supplied by the crosswalk. |
| geographic_level | STRING | national for PHL; region for mapped regional observations. |
| indicator | STRING | Trimmed indicator label with trailing numeric footnote reference removed. |
| level_of_education | STRING | Elementary, Secondary (Junior High School), or Secondary (Senior High School). |
| sex | STRING | Both Sexes, Female, or Male. |
| completion_rate | DECIMAL(6,3) | Completion percentage on a 0–100 scale; NULL for recognized missing values. |
| unit | STRING | percent. |
| raw_value | STRING | Trimmed source measure text, including missing markers. |
| value_status | STRING | Availability or validation classification of the measure. |
| processed_at | TIMESTAMP | Silver processing timestamp assigned to inserted and matched records. |

`processed_at` is the only audit field in Silver. Original records and ingestion metadata remain in Bronze.

`raw_value` and `value_status` preserve measure availability and support data quality checks.

## Value statuses

| Status | Meaning |
|---|---|
| available | Numeric percentage within 0–100. |
| missing_blank | Source measure is NULL or blank. |
| source_marker_two_dots | Source text is `..`; interpretation follows the source publication. |
| source_marker_three_dots | Source text is `...`; interpretation follows the source publication. |
| invalid_numeric | Unrecognized text or failed decimal conversion; blocks the load. |
| invalid_range | Parsed measure outside 0–100; blocks the load. |

Recognized missing observations remain in Silver with NULL measures. Missing values are never converted to zero.

Invalid statuses may appear in staging but must not be loaded into the target.

## Transformation rules

1. Unpivot `c_2021`–`c_2025` into year and raw_value using STACK, preserving missing observations.
2. Trim measure text and cast numeric values to DECIMAL(6,3). Keep the percentage scale without dividing by 100.
3. Remove leading hierarchy dots and trailing numeric footnotes from geolocation for region matching.
4. Normalize region aliases into uppercase alphanumeric keys and derive code hints for recognized labels.
5. Resolve geography using the updated crosswalk:
   - Prefer an exact alias valid for the observation year.
   - Otherwise, use a recognized region code valid for that year.
   - For missing measures, allow a known mapping outside its validity interval to preserve source placeholders.
6. Collapse equivalent mapping candidates and block conflicting best matches.
7. Copy the standardized region_code and region_name from the crosswalk.
8. Remove trailing numeric footnotes from indicator and education-level labels.
9. Classify Philippines as national and other mapped locations as region.
10. Assign or preserve IDs and record processed_at during loading.

The crosswalk uses `source_region`, `region_code`, `region_name`, validity years, and `geographic_level`. The transformation does not filter by `source_code`.

The year list is explicit. Additional observations and revised values within 2021–2025 are supported. Adding another year requires extending the SQL year list.

## IDs and load behavior

- The initial ID base is 8,000,000; the first assigned ID is 8,000,001.
- Existing matched natural keys retain their IDs.
- New keys receive IDs above the current target maximum.
- Sequential allocation requires one concurrent writer.
- Routine refreshes preserve the target table and existing identifiers.

| Source/target situation | Action |
|---|---|
| Natural key exists in both | Update attributes and processed_at; preserve ID. |
| Natural key exists only in source | Insert with a newly allocated ID. |
| Existing record is absent from the current source | Preserve the previously loaded record. |
| Missing measure becomes available | Update the existing record using the same ID. |
| Source location has no mapping or a rate is invalid | Fail validation before the data MERGE. |

Matched rows receive a refreshed processed_at on each successful run, including when business values are unchanged.

The script processes the current source within its configured year scope. It does not rely on an ingestion watermark.

## Target creation and schema cleanup

The SQL creates the schema and target table when absent. It adds completion_rate_id when upgrading an earlier table version without that field.

For earlier Silver versions, the script enables Delta name-based column mapping and removes these legacy columns when present:

- source_indicator
- source_geolocation
- source_level_of_education
- source_drive_file_id
- source_file
- source_content_hash
- source_ingestion_run_id
- source_ingested_at

Existing IDs and remaining columns are retained. Source records and ingestion metadata remain available in Bronze.

The script does not migrate arbitrary incompatible schemas. Schema maintenance and the data MERGE are separate operations; a successful schema change may remain if a later statement fails.

## Validation gates

The SQL checks:

- Unique Bronze dimension combinations before unpivoting.
- No conflicting best crosswalk matches.
- Preservation of observation count after mapping.
- A nonempty source stage.
- Required mapped region fields and indicator values.
- Expected education levels and sex categories.
- No unexpected numeric text or percentages outside 0–100.
- Unique natural keys in staging and the existing target.
- Existing non-null IDs are unique and greater than 8,000,000.
- Legacy target rows without IDs are present in staging for ID assignment.

Recognized missing markers are accepted.

Source completeness and ingestion lineage quality must be checked upstream. Official metadata verification and source reconciliation remain separate validation activities.

## Recorded validation results

The supplied profiling and transformation results show:

| Check | Observed result |
|---|---:|
| Bronze rows | 171 |
| Silver observations | 855 |
| Unmapped rows | 0 |
| Numeric rates | 657 |
| Missing rates | 198 |
| Invalid rates | 0 |
| Duplicate natural keys in the reported stage | 0 |
| Mapped source locations | 19 |

| Year | Available | Two-dot marker | Three-dot marker |
|---|---:|---:|---:|
| 2021 | 162 | 9 | 0 |
| 2022 | 162 | 9 | 0 |
| 2023 | 162 | 9 | 0 |
| 2024 | 171 | 0 | 0 |
| 2025 | 0 | 0 | 171 |

The 27 two-dot observations belong to NIR in 2021–2023. Counts include national records and all sex categories.

The supplied target output on 19 October 2026 contains:

| Check | Observed result |
|---|---|
| Output records | 855 |
| First ID | 8,000,001 |
| Last ID | 8,000,855 |
| Processing timestamp | 2026-10-19T11:30:49.814Z |
| National classification | PHL → national |
| Missing observations | Preserved with NULL measures and source statuses |

These results describe the supplied snapshot. They are not fixed limits for future valid additions.

Rerun behavior, controlled updates, new-key insertion, and failure recovery require separate acceptance checks before unattended scheduling.

## Job execution

1. Run after successful Bronze ingestion and crosswalk maintenance.
2. Execute all SQL statements in order within the same session.
3. Stop execution on the first error.
4. Set Job maximum concurrent runs to 1.
5. Prevent overlapping ingestion, crosswalk changes, and other target writers during execution.
6. Check final schema, natural-key and ID uniqueness, year coverage, missingness, and source reconciliation.
7. Retain validation outputs with Job run evidence.

Before scheduling, verify that:

- An unchanged rerun preserves IDs and row count.
- A corrected measure updates the existing record.
- A new natural key is inserted once.
- Previously loaded records remain available when absent from the current source.
- Invalid input blocks the merge.

When a run fails, inspect the failed assertion, correct the responsible source or mapping, and rerun the complete script. Preserve existing target identifiers.

## Analytical limitations

- The profiled source has no numeric 2025 values. Do not replace missing rates with zero or carry forward 2024 values.
- NIR measures are missing in 2021–2023. Region-name mapping does not harmonize historical boundaries.
- For overall comparisons, choose Both Sexes and a specific education level.
- Do not combine aggregate and sex-specific percentages as additive measures.
- Do not sum completion percentages or derive a national rate from regional averages without valid denominator weights. Use supplied national observations.
- Budget joins must account for education and sex breakdowns to avoid repeating budget amounts.
- Spending comparisons describe associations and do not establish causation.
- Verify the official indicator definition, denominator, reference period, marker meanings, and footnotes before final analytical interpretation.

## Related files

- [Bronze findings](../../profiling/bronze/completion_rate/findings.md)
- [Bronze data dictionary](../../profiling/bronze/completion_rate/data_dictionary.md)
- [Completion rate SQL](../../dbt/models/silver/completion_rate.sql)

Repository destination: `docs/silver/completion_rate.md`.