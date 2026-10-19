# Unemployment Rate — Bronze Findings

Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.unemployment_rate` 
Assigned to: Anjelika Marquez 
Scope: 2021–2025

## Summary

The reported checks cover 1,914 records from one ingested workbook and four source table versions. Regional rate values are present, numeric, and within 0–100. Source versions must be selected before producing one regional rate per year.

These results come from the Databricks outputs supplied during profiling. The final consolidated SQL includes additional checks whose results are still pending.

## Reported check results

| Check | Result |
|---|---|
| Total rows | 1,914 |
| Source files | 1 |
| Missing region, geographic name, indicator, or year | 0 for each field |
| Missing estimates | 10 |
| Nonnumeric nonblank estimates | 0 |
| Negative estimates | 0 |
| Unemployment rates above 100 | 0 |
| Invalid nonblank / negative standard errors | 0 / 0 |
| Invalid nonblank / negative CVs | 0 / 0 |
| Duplicates within the tested source-version key | 0 |
| Regional year/alias mapping | One distinct canonical pair per tested alias and year |
| Rescued rows | 0 |
| Incomplete required lineage | 0 |

Numeric parse checks do not establish statistical validity or source accuracy.

## Source versions

| Source table coverage | Rows |
|---|---:|
| 2021 | 270 |
| 2022 and 2023 | 552 |
| 2023 and 2024 | 544 |
| 2024 and 2025 | 548 |

2023 and 2024 appear in both Preliminary and Final releases. Some values change between releases. These are versioned observations, not automatically duplicate errors.

## Missing estimates

| Year | Area | Source status | Measures missing | Marker |
|---|---|---|---:|---|
| 2022 | Cotabato City, BARMM | Final | 2 | a/ |
| 2022 | Maguindanao del Norte | Final | 2 | c/ |
| 2022 | Maguindanao del Sur | Final | 2 | None supplied |
| 2023 | Cotabato City, Region XII | Preliminary | 2 | b/ |
| 2023 | Maguindanao, BARMM | Preliminary | 2 | d/ |

Each pair contains the unemployed-person estimate and unemployment rate. Keep these NULL values and their markers. Source footnote meanings are not yet verified.

## Regional candidate selection

Proposed rule for the observed snapshot: use Final where supplied; retain the only supplied 2021 and 2025 versions.

| Year | Status | Selected rows | Unique regions | Missing rates | Minimum rate | Maximum rate |
|---|---|---:|---:|---:|---:|---:|
| 2021 | Not specified | 17 | 17 | 0 | 4.012 | 10.612 |
| 2022 | Final | 17 | 17 | 0 | 3.709 | 7.244 |
| 2023 | Final | 17 | 17 | 0 | 2.364 | 5.872 |
| 2024 | Final | 18 | 18 | 0 | 2.501 | 5.646 |
| 2025 | Preliminary | 18 | 18 | 0 | 2.711 | 5.842 |

The reported selection returned 87 rows using DISTINCT. The consolidated profiling SQL removes source deduplication and adds an explicit post-mapping duplicate check. Its rerun is pending. This is a candidate selection, not a validated Silver load.

The rule is specific to this snapshot. A new release requires version review; ingestion timestamps alone do not identify the authoritative estimate.

## 2021 source verification

Reviewed the supplied [2021 reference workbook](https://drive.google.com/file/d/1Mx2Jb2gD2VCwB-R3HJ48tfYlAb-vzzHv). Its table heading and readable notes do not explicitly state Final or Preliminary. Retain Not specified.

The source identifies the Philippine Statistics Authority, 2021 Labor Force Survey, and states that estimates use the 2015 POPCEN-based Population Projection. Its rounding note explains that details may not add to totals.

Small 2021 standard-error and CV values are present in the reference workbook too. Their cross-year comparability remains pending; do not rescale them based only on their magnitude.

## Geography

- Both 2024 CALABARZON labels map to IVA. They are aliases, not separate regions.
- The supplied NIR regional rates begin in the 2024 Final version and continue in 2025 Preliminary.
- Do not fabricate NIR rates for 2021–2023.
- VI, VII, and NIR comparisons require boundary review. Matching canonical codes does not prove consistent geographic coverage across releases or budget sources.

## Lineage

- Source: `05_development_indicators/01_unemployment_rate/Unemployment_2021-2025.xlsm`
- Run: `06348391a60e4b3bb71634792d2a6f73`
- All 1,914 records have the tested required lineage fields.
- Earliest and latest ingestion: `2026-10-18T19:01:01.796Z`.

## Recommended Silver treatment

- Parse whole-year text into INT after validating the original label.
- Store rates as decimals without multiplying or dividing the Percent values.
- Select regional Annual unemployment-rate observations for the regional analysis.
- Preserve estimate status, including Preliminary for 2025 and Not specified for 2021.
- Resolve equivalent crosswalk aliases without multiplying source rows.
- Validate one record per selected year and canonical region.
- Keep all original measures, versions, source markers, and lineage in Bronze.

## Pending checks

- Run the consolidated whole-year validation and post-mapping duplicate check.
- Verify source footnotes a/–d/.
- Verify statistical methodology and 2021 precision-field comparability.
- Review geographic comparability around NIR and VI/VII.
- Validate comparison-year and change fields before using them.
- Assignment owner is not confirmed for this documentation.

## Related files

- [Profiling SQL](profiling.sql)
- [Data dictionary](data_dictionary.md)
