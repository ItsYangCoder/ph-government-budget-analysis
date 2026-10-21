# Population — Bronze Findings

Assigned to: **Razzelle Boreros**  
Documented by: **Razzelle Boreros**  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.population`

## What this dataset contains

Projected population by region, year, age group, and sex. One row represents one combination of these fields.

The supplied report identifies the source as **PSA 2020 Census-Based Population Projections, Table 1**, with projected mid-year population as of **1 July**, covering 2020–2035. Values are in **persons**.

These are projections, not a fresh census count for every year. They can provide population context for regional budget analysis.

## Reported results

The results below come from the supplied findings. They were not rerun against Databricks while preparing this document.

| Check | Reported result |
|---|---|
| Total records | 16,416 |
| Year coverage | 2020–2035 |
| Geography | 17 regions plus the separately reported Philippines total |
| NIR | Not included in this source |
| Missing region, year, population, age group, sex, reference date, or source | 0 |
| Missing age_min | 864, associated with TOTAL |
| Missing age_max | 1,728, associated with TOTAL and 85 AND OVER |
| Exact duplicates, including or excluding ingestion metadata | 0 |
| Repeated region/year/age-group/sex keys | 0 |
| Invalid nonblank numeric values in tested fields | 0 |
| Numeric dash placeholders | 0 |
| Negative or fractional values in tested numeric fields | 0 |
| Population range | 2,100–123,963,500 persons |
| Zero population values | 0 |
| Invalid reference dates or reference-year mismatches | 0 |
| Unexpected age-group or sex labels | 0 |
| Rescued data | NULL throughout |
| Regional TOTAL/BOTH rows for 2021–2025 | 85 |

The supplied report also states that all 16,416 population values and reference dates match the original Excel, with no source records missing from the prepared data. Treat this as a reported source comparison: the attached SQL does not perform that Excel comparison.

## Totals and breakdowns

- TOTAL is the all-age total. Do not add it to its age-group breakdown.
- BOTH is the both-sex total. Do not add it to MALE and FEMALE.
- PHILIPPINES is the source-reported national total, not an additional region.
- A regional national sum must use one TOTAL/BOTH record per region and year.
- A missing population is not zero.

## Regional sum versus source national total

| Year | Regional sum minus Philippines |
|---|---:|
| 2021 | 0 persons |
| 2022 | +100 persons |
| 2023 | +100 persons |
| 2024 | +100 persons |
| 2025 | 0 persons |

The supplied findings say these differences also appear in the original Excel. Preserve them. Do not adjust a region or overwrite the national estimate to force a match.

When reporting a regional sum, label it as a **calculated regional total**. It should not be presented as the source-reported Philippines estimate.

## Expected NULL age limits

| Age group | age_min | age_max |
|---|---:|---:|
| TOTAL | NULL | NULL |
| 0 - 4 | 0 | 4 |
| 85 AND OVER | 85 | NULL |

Other age bands need valid whole-number lower and upper limits that agree with their labels.

## Recommended Silver treatment

| Area | Treatment |
|---|---|
| Scope | Keep 2021–2025 under the current project scope. |
| Geography | Match region labels through the shared crosswalk and validate the result for each year. |
| NIR | Do not invent, split, or fill NIR population without a supported source. |
| Types | Validate whole-number years and ages before casting to INT. Validate nonnegative whole population values before casting to BIGINT. |
| Labels | Trim age-group and sex labels. Preserve the meaning of TOTAL, BOTH, and open-ended age groups. |
| Missing values | Keep expected age-limit NULLs. Preserve missing population as NULL and flag it for review. |
| Keys | Validate canonical region + year + age group + sex after mapping. |
| Projection reference | Keep the 1 July reference-date meaning clear in documentation. |
| Processing time | Use processed_at for Silver processing time; retain ingestion lineage in Bronze. |

The attached SQL proposes regional records for BOTH sexes, keeping age groups including TOTAL. The original findings also mention retaining all sex breakdowns. These are different output scopes: confirm the actual Silver contract before implementing it. Bronze keeps all source records either way.

If Silver excludes PHILIPPINES, its source estimate remains available in Bronze. Any national total calculated from regional records must stay distinguishable from it.

## SQL updates and pending checks

- Removed the notebook-only %sql marker so the file can be used as a plain SQL script.
- Changed temporary numeric parsing from DOUBLE to fixed-precision DECIMAL to avoid floating-point arithmetic for population counts.
- Added age-bound consistency and required lineage checks.
- Rerun the updated SQL before recording these additional checks as passed.
- Confirm one-to-one year-specific crosswalk mappings and post-mapping key uniqueness.
- Confirm the BOTH-only versus all-sex Silver scope and national-total handling.
- Review geography compatibility before comparing this 17-region projection series with datasets that include NIR.
- Regional coverage in this script is checked against labels found in the source; it is not independent proof that every expected official region is present.

## Related files

- [Profiling SQL](profiling.sql)
- [Data dictionary](data_dictionary.md)
