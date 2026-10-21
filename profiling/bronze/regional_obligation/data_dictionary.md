# Regional Obligations — Bronze Data Dictionary

Assigned to: Mia Barroga  
Documented by: Mia Barroga  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.regional_obligations`  
Source: DBM BESF Table B.6.a, regional expenditure allocation tables with actual obligations for 2021–2025. Confirm the publication edition and source page using each record's source fields.

## What one row means

One row is one reported expenditure amount for a year, category, particular, and location label. The source includes agency or fund details, category subtotals, grand totals, and a Total location column. Not every row represents a regional agency amount.

The profiling business key is `year + category + particulars + regions`. Check its uniqueness on each load before using it for Silver. Keep source references to distinguish records from different publications if more files are added.

## Source columns

| Column | Type | Meaning |
|---|---|---|
| source_name | STRING | Source document or file name recorded by extraction. Use it with source_page to trace a value. |
| source_page | STRING | Source page reference. Keep the original text in Bronze. |
| price_basis | STRING | Source series label identifying the reported measure, such as actual obligations. Despite its name, do not assume this is an inflation-adjustment base year. Preserve the exact label. |
| year | STRING | Year the reported amount relates to. The profiling scope is 2021–2025. It is separate from the source publication year. |
| category | STRING | Source budget grouping, such as DEPARTMENTS, SPECIAL PURPOSE FUNDS, AUTOMATIC APPROPRIATIONS, or GRAND TOTAL. Categories may change across years. |
| particulars | STRING | Source agency, fund, or aggregate label. The profiling SQL treats `All` as a category subtotal when the category is not GRAND TOTAL. |
| regions | STRING | Source location label. Includes region labels, Nationwide, Central Office, and Total. This is not yet the canonical project region_code. |
| expenditure_amount | STRING | Reported monetary amount as extracted. Keep numeric text, dash markers, and blanks unchanged in Bronze. Interpret it together with unit_amount. |
| unit_amount | STRING | Source monetary unit. The supplied profiling SQL expects thousand pesos; confirm the observed labels when running it. |

## Ingestion columns

| Column | Type | Meaning |
|---|---|---|
| _rescued_data | STRING | Unexpected fields captured during ingestion. Review any nonblank value. |
| _drive_file_id | STRING | Google Drive ID of the ingested source file. |
| _source_file | STRING | Relative source path recorded by ingestion. This can identify the extracted CSV rather than the original PDF. |
| _landing_file | STRING | Landed source file path in the Unity Catalog volume. |
| _source_modified_at | STRING | Source file modification timestamp. It is not the fiscal year or reporting period. |
| _source_sheet | STRING | Sheet selection recorded by ingestion. A blank or NULL can be expected for sources without worksheets. |
| _content_hash | STRING | Fingerprint of the source file content. |
| _header_map | STRING | Serialized mapping from original headers to normalized Bronze column names. |
| _dataset_hash | STRING | Dataset fingerprint recorded by ingestion. |
| _run_id | STRING | Ingestion run identifier shared by records processed in that run. It is not a row ID. |
| _ingested_at | TIMESTAMP | Time the record was ingested into Bronze. |

## How to read the amounts

- When unit_amount is thousand pesos, `1,000` means ₱1,000,000. Multiply by 1,000 only when explicitly converting to pesos.
- A dash and a blank are different source states. Neither automatically means numeric zero.
- Keep unexpected numeric text visible for review. A failed cast should not silently become zero.
- Reconciliation differences are observations. A small difference is not proof of rounding unless the source precision and tolerance have been verified.
- Actual obligations describe commitments incurred. Do not label them as cash disbursements or payments.

## Geography and totals

| Source pattern | Profiling interpretation | How to use it |
|---|---|---|
| category = GRAND TOTAL | Grand total row | Keep separate from the detail it summarizes. |
| particulars = All, outside GRAND TOTAL | Category subtotal | Use for reconciliation; do not add it to the same category's detail. |
| Other particulars | Agency or fund detail | Retain category and year when identifying the record. |
| regions = Total | Total across source location columns | Do not add it again to the regional/location amounts. |
| regions = Nationwide | Amount reported nationwide | Keep separate from individual regions. Do not allocate it equally across regions. |
| regions = Central Office | Amount reported for the central office | Keep separate from regional amounts. It does not automatically belong to NCR. |
| Other regions labels | Candidate regional records | Resolve through the shared crosswalk and check applicable validity years. |

The shared crosswalk is the reference for canonical names and codes. The profiling SQL checks distinct canonical mappings from the shared crosswalk; its result must still be reviewed for zero or multiple matches. Check aliases and year validity before building Silver. Do not infer historical regional coverage from the current region list alone.

## Bronze and Silver boundaries

Bronze keeps source labels, values, markers, and ingestion metadata. Silver can cast year and amounts, resolve canonical geography, and standardize approved agency aliases after validation.

Profiling retains missing, marker, and invalid amounts separately and performs no Silver writes or currency conversion. Approve marker treatment and units before downstream conversion. This dictionary does not establish Silver readiness or confirm the SQL's expected row counts.

## Related files

- `profiling.sql` — place the Regional Obligations profiling queries alongside this dictionary under this name.
- `findings.md` — Regional Obligations profiling results and decisions.
