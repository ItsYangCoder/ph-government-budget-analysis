# Service Access | Bronze Findings

Assigned to: **Joy**  
Updated: **20 October 2026 (Asia/Manila)**  
Assumed table: `pondolens.dev_bronze.service_access` — confirm actual path before running SQL.

## Evidence and dataset understanding

Computed directly from the 400-row Markdown export in `Pasted text(4).txt`. These are snapshot results, not a live Databricks run. The population examples supplied the profiling structure; their population-specific tests were replaced with percentage and denominator checks. Original PSA/JMP workbooks were not supplied or independently compared.

One row represents country × source area × year × indicator × breakdown type/value × source and unit. Source and denominator must be retained when distinguishing definitions. There are 22 exported columns: 11 business/source fields and 11 ingestion fields. Live data types require DESCRIBE TABLE; a text export cannot establish physical types.

## Completeness

| Check | Snapshot result |
|---|---:|
| Rows | 400 |
| Years | 2021–2025; 80 rows each |
| Indicator labels | 9 |
| Source labels | 5 |
| Areas | 17 regional labels + National |
| Missing measurements | 218 |
| Populated measurements | 182 |
| Missing rescued payload | 400; expected when no rescue occurred |
| Missing source sheet | 400; consistent with CSV ingestion |
| Missing other fields | 0 |
| All-column exact duplicate excess | 0 |
| Business-column exact duplicate excess | 0 |
| Repeated source-aware business-key excess | 0 |

Missing observations do not establish a survey release schedule or mean zero. The export contains placeholder rows for unavailable years. NIR is not present. A region crosswalk cannot derive NIR observations or reallocate Sulu values.

## Project scope and consistency

Select **2022 and 2024**, the three requested labels, **PSA APIS**, Total breakdown. An indicator/year filter alone selects 120 rows, including 12 national JMP observations. APIS-only scope is **108 rows: 102 regional (17 × 2 × 3), plus 6 National**. All 108 measurements are populated and within 0–100. Keep the national rows separately identifiable; for a regional-only Silver contract, retain 102 rows.

| Measure | Unit | Breakdown |
|---|---|---|
| At least basic drinking-water access | % of families | All families |
| Basic sanitation access | % of families | All families |
| Basic handwashing facilities | % of consenting families | Consenting families |

The JMP records with matching indicator names measure population, rural population, or urban population. They must not be merged with APIS family-based measurements. `At least basic sanitation access` is also a separate source label and is outside the selected scope.

## Numeric profiling — selected APIS regional records

Means below are descriptive, unweighted regional means, not national estimates.

| Indicator | Year | Regional rows | Min | Max | Mean | Source National |
|---|---:|---:|---:|---:|---:|---:|
| At least basic drinking-water access | 2022 | 17 | 87.8 | 99.3 | 95.0235 | 96.3 |
| At least basic drinking-water access | 2024 | 17 | 88.2 | 99.6 | 96.5941 | 97.5 |
| Basic sanitation access | 2022 | 17 | 51.6 | 92.5 | 82.2941 | 84.0 |
| Basic sanitation access | 2024 | 17 | 57.1 | 94.3 | 83.0824 | 84.7 |
| Basic handwashing facilities | 2022 | 17 | 75.7 | 97.7 | 91.6294 | 93.2 |
| Basic handwashing facilities | 2024 | 17 | 82.4 | 98.4 | 93.2529 | 94.0 |

## Validity and estimate status

Snapshot values were tested for numeric parsing and 0–100 validity; detailed all-snapshot results appear below. In selected APIS rows, notes describe 2022 as final and 2024 as preliminary. These are claims recorded in source notes, not an independently verified current release status. There is no dedicated estimate-status column in Bronze.

Drinking-water notes state that 2022 basic includes safely managed access; 2024 at least basic was calculated as safely managed plus basic from rounded percentages. Preserve this derivation and potential rounding effects. Access does not establish water quality. Handwashing observations use consenting families, so they are not interchangeable with all-family rates.

## Accuracy and reconciliation

Internal consistency passed for the selected source-aware grain in the supplied snapshot. This does not prove source accuracy.

- National percentages cannot be obtained by summing regional percentages.
- Unweighted regional means need not equal the national estimate.
- Population totals are not suitable weights for family-based or consenting-family estimates. Relevant denominators/survey weights are absent.
- Original-workbook reconciliation: **NOT RUN**. Compare the original Table 1/2/3 cells, year headers, family denominators, final/preliminary status, and 2024 water derivation before claiming a source match.
- Regional mapping and post-mapping uniqueness: **NOT RUN**; current crosswalk contents/schema were not supplied.
- Notes flag BARMM as including Sulu and some regions as having no separate NIR. Preserve the source boundary basis; review compatibility with budget/population geographies before joining.

## Silver treatment

| Area | Recommended treatment |
|---|---|
| Scope | APIS only, 2022/2024, three exact indicators, Total breakdown; 102 regional candidates and 6 separate national observations. |
| Types | Whole-year validation then INT; percentage to DECIMAL with agreed precision or DOUBLE per team contract. No ×100 conversion. |
| Missing values | Preserve NULL; do not fill 2021/2023/2025 or replace missing measurements with zero. |
| Labels | Trim consistently; use explicit indicator mapping, retaining denominator semantics. |
| Geography | Use year-aware shared crosswalk; require exactly one match, no fan-out, no unmapped labels, and unique canonical keys. No unsupported NIR/Sulu redistribution. |
| Keys | Use stable persistent service_access IDs; validate canonical region × year × complete indicator definition. |
| Units | Preserve % of families versus % of consenting families; do not collapse to a generic family denominator. |
| National | Preserve source national estimates separately; never add them to regional rows. |
| Audit | Retain original source/release/derivation notes in Bronze and accessible documentation; set Silver processed_at. |
| Gold | Add three definitions only after Silver is validated; definitions must carry correct denominators. |

## Remaining checks

Confirm Bronze table path and live schema; run profiling.sql against Databricks; verify original source cells and geographic compatibility; validate current crosswalk joins and decide national-row handling. SQL changes no stored Bronze data. A clean local export is not proof the live table or Silver load passed.

## Related files

- [Profiling SQL](profiling.sql)
- [Data dictionary](data_dictionary.md)

## All-snapshot numeric check

Nonblank malformed/nonfinite values: **0**. Out-of-range values: **0**. Observed numeric range: **21.2–99.8**. Numeric checks do not verify the original source.
