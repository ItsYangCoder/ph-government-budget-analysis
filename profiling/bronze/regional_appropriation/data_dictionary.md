# Regional Appropriation — Bronze Data Dictionary

Documented by: **Razzelle Boreros**  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.regional_appropriation`

## Purpose

Stores source appropriation records for PondoLens. These records support budget distribution analysis and comparisons with regional obligations after cleaning and alignment in Silver.

## What one row means

One appropriation record for a year, category, department or fund, geographical area, and stated basis.

Bronze includes both detail records and published totals. Do not sum the entire table to get a national budget total.

## Business columns

These nine columns are STRING in Bronze. The profiling SQL creates temporary parsed values without changing the stored source data.

| Column | Meaning | Handling note |
|---|---|---|
| source_name | Source document or file label captured during preparation. | Keep for tracing records back to the supplied report. |
| source_page | Source page or table location captured during preparation. | Keep as text; it may contain more than a page number. |
| price_basis | Budget basis stated in the source; reported as GAA (Updated). | This is a budget basis, not an inflation-adjustment year. Review unexpected values. |
| year | Budget year stored as text. | Validate the original label before casting to INT. Current scope is 2021–2025. |
| category | Source grouping, such as DEPARTMENTS, SPECIAL PURPOSE FUNDS, or GRAND TOTAL. | Category determines whether a row is detail or aggregate. |
| particulars | Department, fund, or aggregate label. | ALL identifies an aggregate. Proposed Silver name: particular. |
| regions | Source geographical label. | Includes regional labels, Nationwide, Central Office, and Total. Use the crosswalk for canonical geography. |
| expenditure_amount | Source appropriation amount stored as text. | Despite the source column name, this table represents appropriations. Reported unit is thousand pesos. Proposed Silver name: appropriation_amount. |
| unit_amount | Source amount-unit label. | Confirm the label before converting currency units. |

## Ingestion columns

The ingestion contract uses the fields below. The updated profiling SQL checks key lineage fields, but a current DESCRIBE and lineage result should confirm their presence and completeness for this table.

| Column | Expected type | Meaning |
|---|---|---|
| _rescued_data | STRING | Ingestion rescue payload. Review any nonblank value. |
| _drive_file_id | STRING | Google Drive source file ID. |
| _source_file | STRING | Relative path of the ingested file. |
| _landing_file | STRING | Landed file path in the volume. |
| _source_modified_at | STRING | Source file modification time, not the budget approval date. |
| _source_sheet | STRING | Selected sheet, when the source format uses one. |
| _content_hash | STRING | Source-content fingerprint. |
| _header_map | STRING | Original-to-normalized column mapping recorded by ingestion. |
| _dataset_hash | STRING | Dataset fingerprint recorded by ingestion. |
| _run_id | STRING | Ingestion run identifier shared across records. |
| _ingested_at | TIMESTAMP | Time the record was ingested. |

## Amounts and missing values

- A numeric value of 1,000 in thousand pesos represents ₱1,000,000.
- The profiling SQL removes grouping commas before parsing amounts as decimals.
- Dash markers are treated as zero under the documented project rule; publisher-note verification is pending.
- Blank, NULL, and invalid numeric text must remain distinguishable from a valid zero.
- The reconciliation checks run in thousand pesos. Currency conversion belongs in the Silver transformation.

## Geography and totals

- TOTAL is a published geographical total.
- ALL in particulars is an aggregate across the relevant department or fund detail.
- Nationwide and Central Office are valid nonregional allocation labels.
- A source region label is not a canonical region_code.
- The reported 17-region coverage must be preserved unless the source supports a different geography.

## Related files

- [Profiling SQL](profiling.sql)
- [Findings](findings.md)
