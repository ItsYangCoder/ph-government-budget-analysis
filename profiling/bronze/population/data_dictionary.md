# Population — Bronze Data Dictionary

Assigned to: **Razzelle Boreros**  
Documented by: **Razzelle Boreros**  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.population`

## Purpose

Stores population projections for regional budget context. For example, a population denominator can support budget-per-person calculations once the year and geography match.

Population projections are not annual census counts. Do not combine them with a budget geography that has different boundaries without reviewing the match.

## What one row means

One population projection for a region or Philippines, year, age group, and sex.

The supplied snapshot covers **2020–2035**, with **16,416 records**, 17 regions, and the Philippines national total. The proposed project scope is 2021–2025.

## Business columns

These columns are stored as STRING in Bronze according to the supplied findings.

| Column | Meaning | Handling note |
|---|---|---|
| region_name | Source region name or PHILIPPINES. | Match through the crosswalk for canonical codes and names. PHILIPPINES is a national total. |
| age_group | Age band or TOTAL. | TOTAL covers all ages; 85 AND OVER is open-ended. |
| age_min | Inclusive lower age limit. | NULL for TOTAL. Zero is valid for 0 - 4. |
| age_max | Inclusive upper age limit. | NULL for TOTAL and 85 AND OVER. |
| sex | BOTH, MALE, or FEMALE. | BOTH already includes both sexes. |
| year | Projection year stored as text. | Validate a whole year before converting to INT. |
| reference_date | Date to which the projection applies. | Reported as 1 July of the corresponding year. This is not an ingestion date. |
| population | Projected number of persons. | Use whole, nonnegative counts. Do not multiply by 1,000 or replace missing values with zero. |
| source | Source description recorded during preparation. | The supplied findings identify PSA's 2020 Census-Based Population Projections, Table 1. |

## Ingestion columns

The attached profiling SQL references these fields. Confirm their current types using the included schema query.

| Column | Expected type | Meaning |
|---|---|---|
| _rescued_data | STRING | Ingestion rescue payload. Nonblank values need review. |
| _drive_file_id | STRING | Google Drive source file ID. |
| _source_file | STRING | Relative path of the ingested file. |
| _landing_file | STRING | Landed file path in the volume. |
| _source_modified_at | STRING | Source file modification time, not the population reference date. |
| _source_sheet | STRING | Sheet selected for ingestion. |
| _content_hash | STRING | Source-content fingerprint. |
| _header_map | STRING | Original-to-normalized header mapping. |
| _dataset_hash | STRING | Dataset fingerprint recorded during ingestion. |
| _run_id | STRING | Ingestion run identifier shared across records. |
| _ingested_at | TIMESTAMP | Time the record was ingested. |

## Safe aggregation

- For a regional all-age population, filter age_group = TOTAL and sex = BOTH.
- For age-band analysis, exclude TOTAL.
- For male/female comparisons, exclude BOTH.
- Keep the source PHILIPPINES total separate from the sum of regional rows.
- The reported regional sum is 100 persons above the national source value in 2022–2024. Keep that difference visible.
- NIR is absent from this source. Its population must not be inferred from a region-name mapping alone.

## Related files

- [Profiling SQL](profiling.sql)
- [Findings](findings.md)
