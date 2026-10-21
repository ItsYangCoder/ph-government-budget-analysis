# Hospital — Silver Documentation

Assigned to: Joy  
Updated: 19 October 2026 (Asia/Manila)  
Source: `pondolens.dev_bronze.hospital`  
Reference: `pondolens.dev_silver.shared_region_crosswalk`  
Target: `pondolens.dev_silver.hospital`

## Purpose and grain

Standardize regional regulated hospital counts for analysis by year, region, and hospital category.

One row represents **year × region_code × hospital_type**. This combination is the natural key. `hospital_id` is the surrogate identifier.

The profiled source contains **68 records covering 2021–2024 and 17 historical regions**. All records are Government hospitals. Private and Total records are absent, and Negros Island Region is not separately listed.

## Output data dictionary

| Column | Type | Description |
|---|---|---|
| hospital_id | BIGINT for new tables | Surrogate ID starting at 7,000,001; existing matched keys retain their IDs. The earlier table may retain its INT column because CREATE TABLE IF NOT EXISTS does not migrate its type. |
| year | INT | Reporting year. Revised SQL accepts a four-digit year between 1900 and 9999. |
| region_code | STRING | Standard project region code from the shared crosswalk; not an official PSGC code. |
| region_name | STRING | Standard region name supplied by the crosswalk. |
| hospital_type | STRING | Standardized category: Government, Private, or Total. Only Government is present in the profiled source. |
| regulated_hospital_count | INT | Nonnegative whole-number count of regulated hospitals. Must fit the INT type. |
| unit | STRING | hospitals. |
| processed_at | TIMESTAMP | Silver processing timestamp assigned on insert or when tracked attributes change. |

`processed_at` is the only audit field. Original source labels, publication details, coverage notes, and ingestion lineage remain in Bronze rather than being copied into Silver. Exact historical tracing requires separately retained source versions or execution records.

## Transformation rules

1. Trim year and hospital-count text. Keep the raw text in staging so invalid inputs can be detected before writing.
2. Validate year as four digits and cast it to INT.
3. Validate hospital count as digits only, cast it to INT, and require a nonnegative value. Decimal, signed, comma-formatted, blank, and nonnumeric text are rejected rather than silently rounded or removed.
4. Normalize source and crosswalk names by removing punctuation and spaces and uppercasing. Match source aliases and canonical names within their validity years, including the explicit NCR source alias. Copy region_code and region_name from the mapping.
5. Standardize known category labels to Government, Private, or Total. Other categories block the load.
6. Lowercase and trim the unit; require hospitals.
7. Preserve existing IDs for matched natural keys and allocate IDs to new keys.

The staging join is LEFT JOIN so unmatched source records remain visible to validation. Records are not silently discarded through an INNER JOIN or invalid-value WHERE filter.

## Validation gates

Before the data MERGE, the script checks:

- Each normalized alias and source year resolves to one distinct code/name pair; equivalent mappings are collapsed.
- The source stage contains records.
- Years and counts satisfy the accepted format and numeric range.
- All regions have nonblank mapped codes and names.
- Hospital types and units are recognized.
- Source natural keys are unique.
- Existing target IDs and key fields are present; IDs are greater than 7,000,000.
- Existing target natural keys and IDs are unique.

Invalid input stops the load. These checks establish structural and value validity, not proof that the correct source dataset was supplied. Unrelated data with the same structure and valid-looking values can still pass. File routing, source identity, required-header checks, and business reconciliation must also be handled in the ingestion and data-quality workflow.

## IDs and MERGE behavior

The ID base is 7,000,000. New keys receive `current maximum ID + ROW_NUMBER()`, beginning at 7,000,001 for an empty target. Rows are ordered by year, region_code, and hospital_type for allocation.

| Situation | Action |
|---|---|
| Existing key, same region name/count/unit | Leave the row and processed_at unchanged. |
| Existing key, changed region name/count/unit | Update attributes and processed_at; retain hospital_id. |
| Existing key with NULL processed_at | Populate processed_at and refresh tracked attributes. |
| New year/region/category key | Insert with a newly allocated ID. |
| Target key absent from the current source | Retain the target row; no automatic deletion. |
| Unmapped region, invalid value, or duplicate key | Fail before the data MERGE. |

New years are accepted without extending a fixed year list. New region labels require crosswalk entries. Private or Total records can be accommodated if supplied and validated; this does not imply that those categories exist in the current source.

The script reads the current Bronze table each run. It is an upsert over that input, not a changed-record-only scan. A corrected natural key is treated as a new key; the old key remains until separately reconciled.

ID allocation requires a single writer. It is not a durable sequence: manual deletion of the highest IDs can allow reuse later. Retain records and IDs, or introduce a persistent key registry before requiring permanent historical identity across deletions.

## Table creation

The active dbt model creates the target when absent. It does not drop provenance columns, enable column mapping, or migrate an existing ID type. Existing incompatible schemas require a separate reviewed migration.

Run through dbt using the pondolens_script materialization. Sources, dependencies, and target schemas are resolved by dbt. Statements execute in order and stop on the first error; they are not one transaction.

## Recorded validation

The existing profiling and Hospital Silver documentation recorded these results for the earlier implementation:

| Check | Recorded result |
|---|---:|
| Rows / unique IDs | 68 / 68 |
| Regions per year | 17 |
| Year coverage | 2021–2024 |
| Duplicate natural keys | 0 |
| Null IDs, region codes, or hospital counts | 0 |
| Bronze vs Silver row/count-total differences per year | 0 |

| Year | Region-year records | Sum of government hospital counts |
|---|---:|---:|
| 2021 | 17 | 440 |
| 2022 | 17 | 434 |
| 2023 | 17 | 445 |
| 2024 | 17 | 456 |

These counts describe the reported source snapshot. Project connected-build evidence is recorded in [validation notes](../../dbt/VALIDATION.md); build success alone does not establish unchanged IDs or timestamps.

## Job execution and acceptance checks

1. Run after successful Bronze ingestion and crosswalk maintenance.
2. Execute SQL in order and stop on the first error.
3. Set Job maximum concurrent runs to 1. Avoid concurrent manual writes, overlapping ingestion, and crosswalk edits during the Silver load.
4. For the unchanged current snapshot, reconcile target rows and yearly totals against the recorded baseline, provided the target contains no additional retained historical keys.
5. Verify IDs and natural keys are unique and non-null; confirm the documented output columns and compatible types exist.
6. Run again with unchanged input: row count, IDs, values, and processed_at should remain unchanged.
7. In an isolated test schema, revise a count and add a new key. Verify that the changed record keeps its ID, the new key receives a new ID, and processing timestamps reflect the changes.
8. Test invalid values, duplicate keys, and an unmapped region; confirm they block loading rather than dropping records silently.

The temporary staging view is evaluated against its underlying tables; the validation statements and MERGE are not one multi-statement transaction. Prevent concurrent changes to the source and crosswalk while executing the load.

## Analytical limitations

- Hospital counts do not measure beds, staffing, facility size, patient capacity, travel time, or quality of care.
- Current data covers Government hospitals only. Do not describe it as all hospitals or test Total = Government + Private without those categories in the source.
- If Total, Government, and Private rows become available, do not add Total to its component categories.
- Regional alias mapping does not harmonize historical boundary differences. NIR is absent as a separate source region.
- The current source has no 2025 observations; do not impute them.
- Regional sums have not been independently reconciled with national source totals.
- The source_page discrepancy (`Sep-28` in Bronze versus `9-28` in the dictionary) requires original-publication verification. Dropping the Silver provenance column does not resolve that source issue.
- Spending comparisons show associations, not proof that spending caused hospital counts to change.

## Related documentation

- [Bronze findings](../../profiling/bronze/hospital/findings.md)
- [Bronze data dictionary](../../profiling/bronze/hospital/data_dictionary.md)
- [Crosswalk documentation](../shared_region_crosswalk.md)

Active model: [hospital.sql](../../dbt/models/silver/hospital.sql). Tests: [Silver schema](../../dbt/models/silver/schema.yml). Recovery: [ingestion guide](../ingestion.md#pipeline-failures-and-recovery).
