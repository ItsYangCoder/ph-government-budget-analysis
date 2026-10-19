# Regional Appropriation — Bronze Findings

Documented by: **Razzelle Boreros**  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.regional_appropriation`

## What this dataset contains

Government appropriations by year, category, department or fund, and geographical area. One row represents one combination of these fields on a stated price basis.

The supplied profiling report identifies the source as DBM Budget of Expenditures and Sources of Financing (BESF), regional allocation tables on a **GAA (Updated)** basis for 2021–2025. Amounts are reported in **thousand Philippine pesos**.

## Reported results

These results were carried over from the supplied profiling report. They were not rerun against Databricks while preparing this document.

| Check | Reported result |
|---|---|
| Total records | 4,780 |
| Year coverage | 2021–2025 |
| Types | Nine business columns are STRING; _ingested_at is TIMESTAMP |
| NULLs in the nine checked business columns | 0 |
| Duplicate rows across the nine business columns | 0 |
| Geography labels | 17 regional labels plus Nationwide, Central Office, and Total |
| Dash amounts | 1,582 |
| Geographical total comparisons | 239 MATCH; zero differences |
| Department / special purpose fund subtotal comparisons | 200 MATCH; zero differences |
| Grand total comparisons | 100 MATCH; zero differences |

Matching totals show that the tested amounts reconcile within this dataset. They do not independently verify the original publication or prove geographic comparability with other datasets.

## Dash amounts by year

| Year | Dash amounts |
|---|---:|
| 2021 | 204 |
| 2022 | 333 |
| 2023 | 365 |
| 2024 | 344 |
| 2025 | 336 |
| **Total** | **1,582** |

The profiling SQL treats hyphens, en dashes, and em dashes as zero under the team's agreed accounting interpretation. This is a documented project rule. Source-note confirmation is still needed before treating it as a verified publisher definition.

Missing or invalid amounts remain unresolved. They are not converted to zero.

## Labels and totals

- Region labels mix codes and names, such as Region IVA, CARAGA, and National Capital Region.
- Agency labels include acronyms in parentheses. Keep meaningful punctuation and acronyms.
- TOTAL geographical rows and ALL particulars are published aggregates. Mixing them with detail rows would double-count amounts.
- Nationwide and Central Office are nonregional allocations. Keep them identifiable when rebuilding overall totals; do not present them as individual regions.
- This source reports 17 regional labels. Do not add NIR or split allocations without source support.

## Recommended Silver treatment

| Area | Treatment |
|---|---|
| Scope | Keep the agreed 2021–2025 scope. Review new years before extending it. |
| Detail selection | Exclude TOTAL geographical rows and ALL particulars from the detail model. Validate category labels so aggregate rows cannot slip through. |
| Region matching | Use the shared crosswalk and its applicable validity years. Equivalent aliases must not multiply records. |
| Canonical labels | Keep the crosswalk's region_code and region_name. Trim and standardize category and particular labels without removing meaningful text. |
| Column naming | Rename particulars to particular and expenditure_amount to appropriation_amount. The source amount is an appropriation measure here. |
| Types | Validate whole-year labels, then cast to INT. Use an appropriate fixed-precision decimal for money. |
| Currency unit | Convert thousand pesos to pesos exactly once by multiplying by 1,000. Check precision and overflow before writing. |
| Dashes and missing values | Apply the documented dash rule. Preserve genuinely missing amounts as NULL and block invalid numeric text for review. |
| Record key | Validate uniqueness of year + category + particular + region_code after mapping. Review conflicting records rather than silently keeping one. |
| Record ID | Keep IDs stable for existing keys and allocate IDs only to new records. |
| Processing time | Update processed_at when a record is inserted or its stored values change. |
| Traceability | Keep the original source values and ingestion metadata in Bronze. |

These are proposed treatments, not proof that a Silver implementation has passed validation.

## Checks to complete

- Run the updated SQL, including strict year-label, ingestion lineage, and rescued-data checks.
- Review blank strings, literal null strings, invalid numeric values, negative amounts, and candidate-key duplicates. Their result counts were not supplied.
- Verify year-specific crosswalk matches and post-mapping key uniqueness.
- Confirm units, GAA (Updated) basis, and dash meaning against source headings and notes.
- Confirm totals can be rebuilt after detail filtering and currency conversion.
- Review changes in geography before joining to obligations, indicators, or map boundaries.

## Related files

- [Profiling SQL](profiling.sql)
- [Data dictionary](data_dictionary.md)
