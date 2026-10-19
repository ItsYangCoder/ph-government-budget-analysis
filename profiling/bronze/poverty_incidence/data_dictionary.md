# Poverty Incidence — Bronze Data Dictionary

Documented by: **Mia Barroga**  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.poverty_incidence`

## Purpose

Stores poverty estimates, thresholds, precision measures, and source notes. These provide context for regional spending analysis once the geography and reference period are aligned.

## What one row means

One observation for a year, geographic area, and indicator: poverty incidence among families or among population.

National and regional rows have a blank province field. Subregional rows use that field for provinces, NCR districts, or other source areas. Do not assume every province value represents an administrative province.

## Source columns

All source columns below are STRING in Bronze.

| Column | Meaning |
|---|---|
| source_name | Source workbook name recorded during preparation. |
| source_page | Source sheet/table label: tab1 for families, tab2 for population in this snapshot. |
| source_row | Source row reference captured during preparation; not a unique record ID. |
| year | Observation year: 2021, 2023, or 2025. |
| region | Source region label or PHILIPPINES. |
| region_name | Additional source geography label, sometimes an acronym or descriptive name. It is not consistently canonical and may be blank. |
| province | Subregional area label. Blank is expected for national and regional observations. |
| annual_poverty_threshold_per_capita | Annual poverty threshold per person, in Philippine pesos according to the source heading. |
| reference_unit | Indicator label: poverty incidence among families or among population. Despite the name, this field does not store the numeric unit. |
| poverty_incidence_estimate | Poverty incidence estimate in percent. A displayed zero with c/ means below 0.05%. |
| poverty_incidence_coeff_var | Coefficient of variation, a relative precision measure. Numeric values above 10% require caution under the source note. Dash markers are not numeric zeros. |
| poverty_incidence_standard_error | Source standard error associated with the percentage estimate. |
| poverty_incidence_confidence_lower | Lower limit of the source 95% confidence interval. |
| poverty_incidence_confidence_upper | Upper limit of the source 95% confidence interval. |
| notes | Source footnotes and revision markers. Keep them with the values. |

## Ingestion columns

| Column | Type | Meaning |
|---|---|---|
| _rescued_data | STRING | Ingestion rescue payload; review nonblank values. |
| _drive_file_id | STRING | Google Drive source file ID. |
| _source_file | STRING | Relative path of the ingested CSV. |
| _landing_file | STRING | Landed file path in the volume. |
| _source_modified_at | STRING | File modification time, not the estimate reference period or publication date. |
| _source_sheet | STRING | Sheet selection; NULL is expected for CSV ingestion. |
| _content_hash | STRING | Source-content fingerprint. |
| _header_map | STRING | Original-to-normalized header mapping. |
| _dataset_hash | STRING | Dataset fingerprint recorded during ingestion. |
| _run_id | STRING | Ingestion run identifier shared across records. |
| _ingested_at | TIMESTAMP | Record ingestion time. |

## Footnotes from source Tables 1 and 2

| Marker | Meaning |
|---|---|
| a/ | CV and SE describe precision of the estimates. |
| b/ | Estimates with CV above 10% should be used with caution. |
| c/ | Poverty incidence is below 0.05%. |
| 1/ | The 2021–2023 change is statistically significant at the 5% level. |
| 2/ | The 2023–2025 change is statistically significant at the 5% level. |
| r1 | 2021 and 2023 figures for IX and BARMM were revised for consistency with Sulu's transfer to IX in 2025. |
| r2 | 2021 figures for XII and BARMM were revised following the transfer of 63 North Cotabato barangays to BARMM. |

Footnote meanings are table-specific. Do not reuse a marker definition from a different source table without checking it.

## Usage notes

- Keep families and population indicators separate. Their denominators differ.
- Do not sum percentage estimates across areas or geographic levels.
- A displayed zero with c/ must not be described as no poverty.
- Preserve original zeros, dash CVs, and notes in Bronze.
- Source NIR figures exist for 2021, 2023, and 2025. The shared crosswalk only maps NIR for 2024–2025.
- Historical NIR handling belongs in a documented poverty-specific Silver rule. Keep the shared crosswalk unchanged.
- The annual threshold heading alone does not verify the 2025 poverty estimate reference period or release status.

## Related files

- [Profiling SQL](#file-3896419488251234) 
- [Findings](#file-3896419488251233) 