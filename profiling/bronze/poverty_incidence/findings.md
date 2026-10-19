# Poverty Incidence — Bronze Findings
Documented by: **Mia Barroga**  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.poverty_incidence`

## Summary

The profiled snapshot has 644 records covering 2021, 2023, and 2025. It contains poverty incidence among families and among population, with national, regional, and subregional observations.

Results below come from the Databricks outputs supplied during profiling. The consolidated SQL has not been rerun against Databricks during document preparation.

## Reported results

| Check | Result |
|---|---|
| Total records / source files | 644 / 1 |
| Missing year, region, indicator label, estimate, or threshold | 0 for each |
| Rescued rows | 0 |
| Invalid year labels or years outside the observed scope | 0 |
| Repeated tested year/region/subregion/indicator keys | 0 |
| Nonnumeric nonblank measures | Eight dash CV markers; zero in the other five measures |
| Negative numeric measures | 0 |
| Estimates above 100% | 0 |
| Confidence interval ordering issues | 0 |
| Threshold differences between indicators for the same area/year | 0 |
| Incomplete required lineage | 0 |

## Coverage

| Year | National rows | Regional rows | Subregional rows | Total |
|---|---:|---:|---:|---:|
| 2021 | 2 | 36 | 174 | 212 |
| 2023 | 2 | 36 | 178 | 216 |
| 2025 | 2 | 36 | 178 | 216 |

Each indicator has one national row and 18 regional rows per year. Regional detail therefore has 108 candidate records across the three years and two indicators. This is a source count, not a validated Silver output.

2022 and 2024 are absent. Do not manufacture annual observations or interpolate them without a separate, documented methodology.

## Numeric ranges

| Year | Estimate range (%) | Annual threshold range (PHP per person) | Numeric CV range (%) |
|---|---|---|---|
| 2021 | 1.1–53.5 | 23,925.35–35,843.41 | 1.3–33.4 |
| 2023 | 0.3–47.6 | 26,557.31–41,757.21 | 1.4–52.0 |
| 2025 | 0–30.4 | 27,899.33–44,561.49 | 1.7–63.7 |

Source note b/ says estimates with CV above 10% should be used with caution. A high CV is a reliability concern, not automatically an invalid number.

## Eight dash CV markers

The 2025 records for Ilocos Norte, Nueva Ecija, Aklan, and Zamboanga Sibugay have a dash CV for both indicators. Their displayed estimate, SE, and interval limits are zero, and their notes include c/.

The source defines c/ as poverty incidence below 0.05%. These displayed zeros must not be interpreted as proof that no families or people are poor.

Proposed treatment: retain the source value and marker; use numeric NULL for the dash CV in Silver; display the estimate as <0.05% in the dashboard when c/ applies.

## Geography and crosswalk

Strict year-valid matching returned 54 regional year/label combinations:

- 52 matched exactly one canonical code/name pair.
- NIR 2021 and 2023 had no mapping.
- No conflicting mappings were reported.

MIMAROPA has a blank secondary region_name, but its primary region label maps to IVB.

NIR values exist in the supplied source for all three years. Its shared crosswalk validity starts in 2024. Keep the shared crosswalk unchanged, as agreed. Handle NIR 2021/2023 through an explicit poverty-specific Silver rule limited to this verified source and reviewed historical years.

The inspected footnotes do not explicitly explain how historical NIR estimates were reconstructed. Preserving source values does not prove that they use the same geography as historical budgets.

Source revisions r1 and r2 also affect IX, XII, and BARMM. A matching region code alone does not establish cross-dataset boundary compatibility.

## Source verification

Reviewed [the supplied reference workbook](https://drive.google.com/file/d/1WACHryac2g7VYd7vEiIjK3AxZwM_M80y/view) (`05_poverty_incidence_2021_2023_2025.xlsx`, Drive file ID `1WACHryac2g7VYd7vEiIjK3AxZwM_M80y`):

- Table 1 contains thresholds and poverty incidence among families.
- Table 2 contains thresholds and poverty incidence among population.
- Both identify estimates in percent, annual thresholds in PHP, and 95% confidence intervals.
- Notes explain precision, below-0.05% estimates, significance markers, and the IX/XII/BARMM revisions.

The workbook has 2025 columns. The annual threshold heading alone does not establish the poverty estimates' full-year reference period or release status. Those remain pending publication verification.

## Lineage

- Source CSV: `05_development_indicators/02_poverty_incidence/poverty_incidence_2021_2023_2025.csv`
- Run: `06348391a60e4b3bb71634792d2a6f73`
- All 644 records have the tested required lineage fields.
- Earliest and latest ingestion: `2026-10-18T19:00:16.822Z`.

## Recommended Silver treatment

- Select regional observations for the agreed regional model. Keep national and subregional source records in Bronze.
- Keep families and population as separate indicators.
- Parse money and percentages as fixed-precision decimals. Do not multiply percentage estimates by 100.
- Preserve source notes and precision markers alongside numeric values or explicit status fields.
- Validate one record per year + canonical region_code + indicator after mapping.
- Apply the narrow historical NIR rule without changing the shared crosswalk.
- Keep existing IDs stable, insert new keys, and update changed records.
- Confirm the reference period and geography before making spending comparisons.

## Pending validation

- Rerun the consolidated SQL against the current Bronze snapshot.
- Verify the source publication, reference period, and release status for 2025.
- Review historical geography interpretation and implement/test the poverty-specific NIR rule.
- Validate post-mapping uniqueness before loading Silver.
- A complete original-workbook-to-CSV value reconciliation has not been performed here.

## Related files

- [Profiling SQL](#file-3896419488251234) 
- [Data dictionary](#file-3896419488251235)
