# Shared Region Crosswalk

Assigned to: Christine Joy Balansay
Updated: 21 October 2026 (Asia/Manila)
Default table: `pondolens.dev_silver.shared_region_crosswalk`
Model: [shared_region_crosswalk.sql](../dbt/models/silver/shared_region_crosswalk.sql)

## Purpose

Map source region labels to the project’s standard codes and names. Silver models use this lookup before records reach Gold.

One row stores a source alias and its year range. Several aliases can point to the same region. Codes such as `IVA` and `IVB` are project codes, not PSGC identifiers.

## Data dictionary

| Column | Type | Meaning |
|---|---|---|
| source_region | STRING | Source alias used for matching. |
| region_code | STRING | Standard project code. It repeats across aliases. |
| region_name | STRING | Standard display name. |
| valid_from_year | INT | First valid year, inclusive. |
| valid_to_year | INT | Last valid year, inclusive. |
| source_code | STRING | Optional code from the source. |
| geographic_level | STRING | Crosswalk level: `region`, `nationwide`, or `other`. Consuming models apply their own output conventions. |

## Loading and matching

The dbt model creates the table when missing, then merges the approved aliases. The MERGE matches the exact stored `source_region`, updates mapped attributes, and inserts missing aliases. For matched aliases, it keeps the earliest start year and latest end year. It does not delete other existing aliases.

Each Silver model prepares its source labels before matching. Depending on the dataset, it uses aliases, canonical names, codes, and year validity. Do not join directly to every crosswalk row by code: repeated aliases can multiply records. Resolve one distinct mapping for each source record and year.

NIR’s seeded alias is valid for 2024–2025. Historical exceptions belong in the affected dataset’s documented rules; do not extend shared validity just to make a load pass. `PHL` is national and `CO` is Central Office, not a region. Nationwide handling is dataset-specific.

## Checks and maintenance

Run `dbt build --threads 1` to build dependencies and run tests. Crosswalk checks cover required fields, validity ranges, and conflicting mappings for the same normalized alias in overlapping years. A repeated alias is not automatically a conflict if it resolves to the same mapping.

Review new aliases against the source before adding them. Check dependent datasets after a mapping change. Matching names does not resolve historical boundary differences or redistribute source values.

There is no fixed expected row count: it depends on the approved aliases and existing entries. Current values come from the model and the selected target table, not earlier profiling snapshots.

## Related files

- [Silver column definitions and tests](../dbt/models/silver/schema.yml)
- [Conflicting mapping test](../dbt/tests/crosswalk_conflicts.sql)
- [Validity test](../dbt/tests/crosswalk_validity.sql)
- [Hospital rules](silver/hospital.md)
- [Completion rate rules](silver/completion_rate.md)
- [Migration notes](../dbt/MIGRATION.md)
