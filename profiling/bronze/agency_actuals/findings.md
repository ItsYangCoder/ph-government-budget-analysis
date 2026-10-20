# Agency Actuals — Bronze Profiling Findings

Assigned to: Mia Barroga  
Documented by: Mia Barroga  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.agency_actuals`

## Status

Profiling results are recorded below. The dataset is retained for reference and possible future analysis. Silver treatment is still pending because of source inconsistencies, marker interpretation, and a confirmed workbook-to-CSV precision difference in one checked record.

The SQL in this folder was assembled from the profiling checks and reported results. It has not been rerun against Databricks as a complete file. Review result changes after any new ingestion.

## Snapshot

| Year | Rows | Layout |
|---|---:|---|
| 2021 | 2,068 | fiscal_year / value |
| 2022 | 1,986 | fiscal_year / value |
| 2023 | 2,020 | fiscal_year / value |
| 2024 | 1,777 | year / amount / percent_amount |
| 2025 | 1,777 | year / amount / percent_amount |
| Total | 9,628 | Two source layouts |

Source folder: `01_agency_actuals/`, files `01_agency_actuals_2021.csv` through `01_agency_actuals_2025.csv`.

All five files have zero rescued rows and zero incomplete ingestion-lineage rows in the reported checks. Run ID: `06348391a60e4b3bb71634792d2a6f73`. All records have ingestion timestamp `2026-10-18T18:59:36.736+00:00`.

## Structure and completeness

2024 and 2025 each contain 1,630 monetary rows and 147 percentage rows. Each has 35 blank particulars, all belonging to Grand Total category_total records. Keep those rows in Bronze.

The checked source-coordinate keys returned no duplicates: source file, sheet and cell for 2021–2023; source file, page, row, row type, category, stage, expense class, percentage type and unit for 2024–2025. This does not establish a universal agency business key.

All 2021–2023 rows have source_cell references. All 2024–2025 rows lack source_cell but have source_row references. This is a layout difference, not missing ingestion lineage.

## Numeric values and markers

| Year | Monetary rows | Dash markers | Negative monetary values | Fractional monetary values |
|---|---:|---:|---:|---:|
| 2021 | 1,911 | 0 | 80 | 0 |
| 2022 | 1,879 | 0 | 64 | 0 |
| 2023 | 1,911 | 0 | 56 | 0 |
| 2024 | 1,630 | 394 | 44 | 1,006 |
| 2025 | 1,630 | 415 | 49 | 1,018 |

No missing monetary measures or unrecognized monetary numeric text were reported, apart from recognized dash markers. Earlier numeric values and value_as_shown are separate fields; a numeric zero alone does not prove how the workbook displayed that cell.

Percentage checks must remove the `%` suffix before parsing. After that correction, 2021–2023 percentages all parsed. 2024 and 2025 each have six `#DIV/0!` markers. All parsed percentages are between 0 and 100.

The 12 formula-error rows belong to Autonomous Region in Muslim Mindanao and Joint Legislative-Executive Councils, with three rate measures each year. Their supporting extracted monetary values are dashes. Keep the error marker; do not turn it into 0%.

Negative Adjustments are present across years. Other negative values include Unobligated Allotments for DOTr and The Judiciary, and 2025 Total Available Appropriations for Automatic Appropriations / Other Automatic. Negative values need context; do not reject them automatically.

## Expense-class reconciliation

Compared each reported Total against PS + MOOE + FINEX + CO. Dash-containing groups were excluded from numeric reconciliation.

| Year | Exact matches | Differences | Maximum absolute difference, thousand pesos | Dash-only review groups |
|---|---:|---:|---:|---:|
| 2021 | 260 | 100 | 1 | 0 |
| 2022 | 246 | 108 | 2 | 0 |
| 2023 | 282 | 78 | 1 | 0 |
| 2024 | 52 | 16 | 0.00001 | 238 |
| 2025 | 15 | 19 | 0.00001 | 272 |

All review groups were caused by dashes. No additional missing/repeated class structure was reported. Partial sums from marker-containing groups are not confirmed discrepancies. Small differences are observed; their cause has not been established as rounding.

## Budget-stage equations

Checked Appropriations + Adjustments = Total Available Appropriations; Allotments − Obligations = Unobligated Allotments; and Total Available Appropriations − Allotments = Unreleased Appropriations.

For 2021–2023, every reported equation difference has maximum absolute magnitude of 1 thousand pesos. For 2024–2025:

| Year | Equation | Match | Difference | Marker review | Maximum absolute difference, thousand pesos |
|---|---|---:|---:|---:|---:|
| 2024 | Appropriations + Adjustments | 137 | 40 | 78 | 7,924,464.47204 |
| 2024 | Allotments − Obligations | 120 | 63 | 72 | 0.275 |
| 2024 | Available − Allotments | 8 | 16 | 27 | 0.00001 |
| 2025 | Appropriations + Adjustments | 150 | 35 | 70 | 0.774 |
| 2025 | Allotments − Obligations | 124 | 52 | 79 | 0.000008 |
| 2025 | Available − Allotments | 16 | 18 | 17 | 0.0000003 |

No REVIEW_STRUCTURE results were reported. The cross-sheet checks rely on the extracted row references and labels; a unique match is not a substitute for complete source-coordinate verification.

## Confirmed record to revisit: Office of the President, 2024

Source page SUMMARY, source row 9, MOOE:

| Field | Workbook readable value | Extracted CSV | Bronze |
|---|---:|---|---|
| Appropriations | 1,222,391 | 1222391 | 1222391 |
| Adjustments | −75,631.476 | (75,631) | (75,631) |
| Total Available Appropriations | 9,071,224.47204 | 9071224.47204 | 9071224.47204 |

The Appropriations MOOE amount repeats the PS amount and does not reconcile with the source total. The inconsistency is already present in the workbook readable contents. Do not infer or overwrite a corrected value from arithmetic alone.

The adjustment lost 0.476 thousand pesos (₱476) between the workbook value and the CSV. The checked CSV and Bronze agree, so ingestion did not introduce this particular precision difference. The exact preparation/extraction step responsible is not yet verified. Do not assume every parenthesized value is affected.

## Source context

The readable 2021 workbook states January 1–December 31, 2021 and thousand pesos. Its notes define unobligated balances as allotments less obligations, and unreleased appropriations as total available appropriations less allotments.

The readable 2024 workbook states January 1–December 31, 2024 and thousand pesos. Some numeric zero cells appear as dashes in the extracted CSV. This supports reviewing formatting, but does not establish one universal dash rule.

The 2025 original workbook was located, but the attempted readable fetch returned no usable contents. Its detailed formulas, formatting, notes and reporting period have not been verified here.

- [2021 workbook](https://drive.google.com/file/d/169JBR5KZzh4-8iVLZDGr_Ee48rpAWKid/view)
- [2024 workbook](https://drive.google.com/file/d/1GCIeHfPj4SQlU4bYZEtIpFQ2tG3WXVWc/view)
- [2024 extracted CSV](https://drive.google.com/file/d/1s4fN0-G14KvK_vByiwmfYtWTaYwHyejs/view)
- [2025 workbook](https://drive.google.com/file/d/15_isv6zIuWPxiSMXqCVv5s4nxUn_hYHW/view)

## Before building Silver

- Preserve reported amounts, source markers, and hierarchy in Bronze.
- Compare underlying workbook cell values and display formatting against CSV output, especially parenthesized amounts.
- Flag the Office of the President inconsistency until a source-backed correction is available.
- Parse parentheses as negative and percentage suffixes separately. Keep error and dash markers alongside nullable parsed measures.
- Choose an explicit analysis grain before aggregating. Keep totals separate from the detail they summarize.
- Verify percentage denominators, source reporting periods and appropriate precision/tolerances. Do not label every equation difference as an execution gap or overspending.

## Related files

- [Profiling SQL](profiling.sql)
- [Data dictionary](data_dictionary.md)
