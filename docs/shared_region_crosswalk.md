# Shared Region Crosswalk

Assigned to: Joy  
Updated: 19 October 2026 (Asia/Manila)  
Table: `pondolens.dev_silver.shared_region_crosswalk`  
Setup SQL: `sql/silver/shared_region_crosswalk.sql`

## Purpose

Map different source region labels to consistent project region codes and names. Silver transformations use this shared lookup so datasets can join using the same region convention.

One row represents **one source-region alias**. The join key is `UPPER(TRIM(source_region_name))` and must be unique. Multiple aliases may map to the same region_code.

## Data dictionary

| Column | Type | Description |
|---|---|---|
| source_region_name | STRING | Source label or prepared matching label accepted by a Silver transformation. Required and unique after uppercase/trim normalization. |
| region_code | STRING | Standard project region code, such as NCR, CAR, IVA, or IVB. Required; may repeat across aliases. |
| region_name | STRING | Standard display name, such as National Capital Region or CALABARZON. Required. |

These short codes are project conventions, not official PSGC codes. The table has no surrogate ID or processing timestamp.

## Mapping coverage

| Mapping set | Contents | Setup status |
|---|---|---|
| Original hospital mappings | 31 aliases for 17 historical regions | Included in Joy's restored setup SQL. |
| Completion rate additions | 18 aliases, including Philippines and NIR | Loaded separately through the completion rate alias MERGE. Not included in the restored 31-row SQL block. |

With both mapping sets and no other changes, the expected table contains **49 aliases**, covering **18 regions plus the national Philippines code PHL**. This is a combined expected state, not a row-count limit or a newly executed validation result.

Examples:

| source_region_name | region_code | region_name |
|---|---|---|
| NCR - National Capital Region | NCR | National Capital Region |
| NCR National Capital Region | NCR | National Capital Region |
| Region IV-A CALABARZON | IVA | CALABARZON |
| Region IV A CALABARZON | IVA | CALABARZON |
| MIMAROPA Region | IVB | MIMAROPA |

The separately loaded completion rate aliases include National Capital Region (NCR), Region IV-A, Negros Island Region (NIR), and PHILIPPINES.

## Setup and maintenance

1. Run the setup SQL before dependent Silver transformations.
2. CREATE TABLE IF NOT EXISTS creates the table only when absent.
3. The insert-only MERGE matches aliases using uppercase and trim normalization.
4. Missing aliases are inserted. Existing aliases, codes, and names are retained; the script does not update or delete them.
5. Rerunning the same mapping block does not add duplicates to an already valid table. Existing duplicates must be resolved separately.
6. Add new aliases only after verifying their intended region. Correcting an existing mapping requires an explicit reviewed update; editing the VALUES block alone will not change a matched row.

Do not rebuild the shared table with CREATE OR REPLACE using only one dataset's mapping set: that can remove aliases needed by other transformations.

For a fresh environment, run both mapping blocks before completion rate processing. The 31 hospital mappings alone are insufficient to reproduce the combined crosswalk.

## How Silver uses the lookup

Hospital matches the trimmed source region label directly, ignoring letter case.

Completion rate first removes leading hierarchy dots and trailing numeric footnote references, then matches the prepared label. For example, `..Region IV-A 2/` becomes `Region IV-A`.

```sql
SELECT
    h.region_name AS source_region,
    x.region_code,
    x.region_name
FROM pondolens.dev_bronze.hospital AS h
LEFT JOIN pondolens.dev_silver.shared_region_crosswalk AS x
    ON UPPER(TRIM(h.region_name))
        = UPPER(TRIM(x.source_region_name));
```

Dependent Silver loads should fail on unmatched locations rather than silently exclude source rows.

## Validation

Previous supplied results confirmed:

- The original table contained 31 hospital aliases.
- Duplicate normalized alias checking returned no rows.
- The completion rate alias MERGE inserted 18 rows.
- All 19 distinct completion rate locations mapped successfully, with no NULL region_code.

The restored standalone 31-row script has not been independently rerun as part of this documentation task.

Ongoing checks should confirm nonblank fields, unique normalized aliases, consistent names for each code, and complete mapping coverage for each dependent dataset. Do not test region_code as unique: aliases intentionally share codes.

## Limitations

- Alias mapping standardizes labels; it does not resolve historical regional boundary changes or redistribute counts between regions.
- Hospital uses 17 historical source regions, while completion rate includes NIR and a national record. A successful name mapping does not guarantee comparable territories across years or datasets.
- PHL is national, not a region; downstream models must distinguish it when aggregating.
- Source footnote meanings require separate verification. Removing footnote markers for matching does not establish their meaning.
- New datasets may introduce labels not covered by either existing mapping block.

## Future dbt migration

When dbt is configured, consolidate the complete approved mapping set into `dbt/seeds/shared_region_crosswalk.csv` and configure its destination as `pondolens.dev_silver.shared_region_crosswalk`. Retire the manual mapping load after migration so one authoritative mapping is maintained.

## Related documentation

- [Hospital Silver](docs/silver/hospital.md)
- [Completion Rate Silver](docs/silver/completion_rate.md)

Repository destination: `docs/silver/shared_region_crosswalk.md`. Consolidate older crosswalk documentation into this file after reviewing references.
