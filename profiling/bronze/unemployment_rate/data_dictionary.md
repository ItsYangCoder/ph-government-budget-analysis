# Unemployment Rate — Bronze Data Dictionary

Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.unemployment_rate`  
Source: `05_development_indicators/01_unemployment_rate/Unemployment_2021-2025.xlsm`  
Assigned to: Anjelika Marquez

## Purpose

Stores unemployment estimates and their source context. Regional unemployment rates support comparisons with regional spending in PondoLens.

## What one row means

One observation for a geographic area, year, indicator, and source table version. The same area and year may appear in both Preliminary and Final versions.

The snapshot has 1,914 rows covering 2021–2025. Country, region, province, city, and municipality records are stored together.

## Source columns

All source columns are STRING in Bronze.

| Column | Meaning |
|---|---|
| source_name | Source workbook label recorded during preparation. |
| source_page | Original sheet/page label recorded during preparation; observed as Sheet1. |
| region | Parent region or national label. It is not always the observation's geographic area. |
| year | Observation year, stored as text such as 2023.0. |
| unit | Percent for unemployment rate; Thousand persons for unemployed population. |
| geographic_level | Country, region, province, city, or municipality. |
| source_table | Source table identifier; observed as Table 3. |
| source_file | Original workbook name recorded during preparation. Separate from ingestion _source_file. |
| geographic_name | Area to which the observation applies. |
| indicator | Unemployment rate or Number of unemployed persons. |
| value | Source estimate. Missing values remain NULL. |
| standard_error | Source-reported standard error for the estimate, in the corresponding measure's units. |
| coefficient_of_variation_percent | Source-reported relative precision measure. It is not a margin of error. |
| estimate_status | Final, Preliminary, or Not specified. The supplied 2021 source does not explicitly label its revision status. |
| frequency | Reporting frequency; observed as Annual. |
| table_version | Full table title identifying the source release/version. |
| source_cell | Original estimate cell reference captured during preparation. |
| value_source_marker | Footnote marker associated with the estimate; observed missing-value markers include a/, b/, c/, and d/. Meanings require source footnotes. |
| standard_error_source_marker | Source marker attached to the standard error, when present. |
| coefficient_of_variation_source_marker | Source marker attached to the CV, when present. |
| comparison_year | Reference year used for the supplied comparison. May be NULL. |
| change_from_comparison_year | Source-supplied change against the comparison year. Negative changes can be valid. |
| change_unit | Unit of change, such as Percentage points or Thousand persons. |
| change_source_marker | Source marker associated with the change. |

## Ingestion columns

| Column | Type | Meaning |
|---|---|---|
| _rescued_data | STRING | Ingestion rescue payload; review any nonblank value. |
| _drive_file_id | STRING | Google Drive source file ID. |
| _source_file | STRING | Relative path of the ingested file. |
| _landing_file | STRING | Landed file path in the volume. |
| _source_modified_at | STRING | Source file modification timestamp, not the estimate release date. |
| _source_sheet | STRING | Ingested sheet; Long Form in this snapshot. |
| _content_hash | STRING | Source-content fingerprint. |
| _header_map | STRING | Serialized original-to-normalized header mapping. |
| _dataset_hash | STRING | Dataset fingerprint recorded by ingestion. |
| _run_id | STRING | Ingestion run identifier shared across records. |
| _ingested_at | TIMESTAMP | Record ingestion time. |

## Usage notes

- Preserve all source versions and metadata in Bronze.
- Do not sum unemployment rates or mix them with unemployed-person counts.
- Thousand persons is a scaled population estimate, not a raw person count.
- Use geographic_level to distinguish regional observations from their child areas.
- Match region aliases through the shared crosswalk using the observation year.
- Keep missing estimates as NULL; source markers do not mean zero.
- Standard errors, CVs, and comparison fields need their own checks before analytical use.

## Related files

- [Profiling SQL](profiling.sql)
- [Findings](findings.md)
