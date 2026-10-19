# Completion Rate — Silver Documentation

Assigned to: Rhea  
Updated: 19 October 2026 (Asia/Manila)  
Source: `pondolens.dev_bronze.completion_rate`  
Reference: `pondolens.dev_silver.shared_region_crosswalk`  
Target: `pondolens.dev_silver.completion_rate`  
SQL: `sql/silver/completion_rate.sql`  
Scope: source year labels 2021–2025

## Purpose and grain

Standardize education completion percentages by year, location, education level, and sex. Completion rates are percentages, not graduate headcounts. The official denominator, school-year interpretation, and source footnotes still require verification.

One row represents **indicator × year × region_code × level_of_education × sex**. This is the natural key. `completion_rate_id` is the surrogate identifier.

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
| processed_at | TIMESTAMP | Silver processing timestamp; refreshed for each matched row on every successful load. |

`processed_at` is the only audit field. Silver does not retain `source_*` lineage columns or original footnoted dimension labels. Original records and ingestion metadata remain in Bronze. Without a source run/version reference in Silver, exact reconstruction of a past Silver row requires separately retained source versions or execution records.

`raw_value` and `value_status` describe measure availability; they are not ingestion lineage fields.

## Value statuses

| Status | Meaning |
|---|---|
| available | Numeric percentage within 0–100. |
| missing_blank | Source measure is NULL or blank. |
| source_marker_two_dots | Source text is `..`; official marker meaning is pending verification. |
| source_marker_three_dots | Source text is `...`; official marker meaning is pending verification. |
| invalid_numeric | Unrecognized text or failed decimal conversion; blocks the load. |
| invalid_range | Parsed measure outside 0–100; blocks the load. |

Recognized missing observations remain in Silver with NULL measures. Invalid statuses may appear in staging but must not be loaded by this script.

## Transformation rules

1. Unpivot `c_2021`–`c_2025` into year and raw_value using STACK, preserving missing observations.
2. Trim measure text and cast numeric values to DECIMAL(6,3). Keep the percentage scale; do not divide by 100.
3. For region matching, strip leading hierarchy dots and trailing numeric footnote references from geolocation.
4. Match the prepared label to the shared crosswalk using uppercase and trim normalization. Copy region_code and region_name; fail for unmatched locations.
5. Remove trailing numeric footnote references from indicator and education-level display labels. This label cleanup does not resolve the footnotes' meanings.
6. Classify Philippines as national and other mapped locations as region. Preserve education and sex categories separately.
7. Assign or preserve IDs, then record processed_at during the load.

The year list is explicit. Additional observations and revised values within 2021–2025 are supported. Adding 2026 or later requires extending the SQL year list.

## IDs and load behavior

- The initial ID base is 8,000,000; the first assigned ID is 8,000,001.
- Existing matched natural keys retain their IDs.
- Unassigned keys receive IDs above the current target maximum using ROW_NUMBER.
- In an initially unassigned 855-key snapshot, the expected range is 8,000,001–8,000,855. Final assigned-ID results have not yet been provided for verification.
- This is single-writer allocation, not a durable sequence. Deleting the highest IDs can allow those numbers to be reused. A deleted key that reappears is not guaranteed its former ID. Do not use these IDs as permanent historical identities across deletion/reinsertion without a persistent key registry.

| Source/target situation | Action |
|---|---|
| Natural key exists in both | Update attributes and processed_at; preserve ID. |
| Natural key exists only in source | Insert with a newly allocated ID. |
| Target key is absent from source and target year is 2021–2025 | Delete from Silver. |
| Target row is outside 2021–2025 | Outside the deletion clause's scope. |
| Source location has no mapping or a rate is invalid | Fail before the data MERGE. |

Deletion assumes a complete, authoritative Bronze snapshot. The nonempty-source validation does not establish completeness. A partial but nonempty source can cause unintended deletions. Verify ingestion success and source coverage before unattended deletion runs; do not use this deletion behavior for incremental source batches.

Matched rows are updated on reruns even when business values are unchanged, so processed_at changes. The script reads the current source snapshot each time; it is not a new-record-only transformation.

## Target creation and schema cleanup

The SQL creates the schema and target table when absent. It adds completion_rate_id if upgrading the earlier table version without that field.

For the earlier wide Silver schema, the script enables Delta name-based column mapping and removes these columns when present:

- source_indicator
- source_geolocation
- source_level_of_education
- source_drive_file_id
- source_file
- source_content_hash
- source_ingestion_run_id
- source_ingested_at

This is a schema-level removal; existing IDs and remaining columns are retained. Old Delta versions and physical files can retain dropped values until separately managed through normal retention procedures. Column mapping can upgrade table protocol requirements; downstream readers must support the feature.

The script does not migrate arbitrary incompatible schema changes. Schema changes and the data MERGE are separate operations, so an error can occur after schema cleanup has succeeded.

## Validation gates

The SQL checks:

- No duplicate crosswalk aliases after uppercase/trim normalization.
- A nonempty source stage.
- Required mapped region fields and indicator values.
- Expected education levels and sex categories.
- No unexpected numeric text or rates outside 0–100.
- Unique natural keys in the stage and existing target.
- Existing non-null IDs are unique and greater than 8,000,000.
- Legacy target rows without IDs are present in the stage so IDs can be assigned.

Missing markers are allowed. Source lineage completeness is not checked by the revised Silver script because lineage columns are no longer selected. Source completeness, official metadata verification, and source-total reconciliation require separate checks.

## Recorded validation results

Rhea supplied these Databricks results for the transformation stage on 19 October 2026:

| Check | Observed result |
|---|---:|
| Total staged rows | 855 |
| Unmapped rows | 0 |
| Numeric rates | 657 |
| Missing rates | 198 |
| Invalid rates | 0 |
| Duplicate natural keys | 0 |
| Mapped source locations | 19 |

| Year | Available | Two-dot marker | Three-dot marker |
|---|---:|---:|---:|
| 2021 | 162 | 9 | 0 |
| 2022 | 162 | 9 | 0 |
| 2023 | 162 | 9 | 0 |
| 2024 | 171 | 0 | 0 |
| 2025 | 0 | 0 | 171 |

The 27 two-dot observations all belong to NIR in 2021–2023. Counts include national records and all sex categories. They describe the tested snapshot, not fixed limits for future valid additions.

These results validate the transformation stage. Final execution of the latest lineage-removal script, target schema/counts, ID allocation, repeat-run behavior, and update/insert/delete behavior have not yet been supplied as execution evidence.

## Job execution

1. Run after successful, complete Bronze ingestion and crosswalk maintenance.
2. Execute all SQL statements in order and stop on the first error.
3. Set Job maximum concurrent runs to 1. Avoid concurrent manual writers and other jobs writing this target.
4. Prevent overlapping ingestion and crosswalk changes while Silver runs: the temporary view is evaluated against its underlying tables.
5. Validate final target schema, natural-key/ID uniqueness, counts, missingness, and data reconciliation after deployment. Test reruns and controlled source changes before unattended scheduling.

## Analytical limitations

- The profiled source has no numeric 2025 values. Do not replace missing rates with zero or carry forward 2024.
- NIR measures are missing in 2021–2023. Region-name mapping does not harmonize historical boundaries.
- For overall comparisons, choose Both Sexes and a specific education level. Do not add aggregate and sex-specific percentages.
- Do not sum completion percentages or average regional rates into a national rate without valid denominator weights. Use supplied national observations.
- Budget joins must account for education and sex breakdowns to avoid repeating budget amounts.
- Spending comparisons are descriptive associations, not proof of causation.
- Verify the official indicator definition, denominator, year-to-school-year interpretation, marker meanings, and source footnotes before final analytical interpretation.

## Related files

- [findings.md](#file-2743717085657363)
- [data_dictionary.md](#file-2743717085657362)
- [completion_rate.sql](#file-2743717085656925)

Repository destination: `docs/silver/completion_rate.md`.
