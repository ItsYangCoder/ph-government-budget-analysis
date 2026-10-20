# Agency Actuals — Bronze Data Dictionary

Assigned to: Mia Barroga  
Documented by: Mia Barroga  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.agency_actuals`

## What one row means

One row is one reported amount or percentage for a source row and budget stage. It can represent an agency, a subtotal, a sub-item, or a grand total. It is not always one agency.

## Source columns

| Column | Type | Meaning |
|---|---|---|
| fiscal_year | STRING | Fiscal year in the 2021–2023 layout. |
| statement_page | STRING | Source statement page label from the earlier layout. |
| row_no | STRING | Row reference in the earlier extracted layout; not an agency ID. |
| particulars | STRING | Agency, section, or sub-item label. Blank for the 2024–2025 Grand Total rows. |
| row_group | STRING | Source hierarchy group in the earlier layout. |
| row_type | STRING | Source row classification. Earlier values include Agency, Section total, Sub-item; later values include agency_total, category_total, line_item, sub_line_item. |
| column_group | STRING | Budget stage or rate label in the earlier layout. |
| class | STRING | Earlier expense class: PS, MOOE, FINEX, CO, Total, or N/A. CO means capital outlays here. |
| value | STRING | Earlier extracted measure. Interpret using unit and column_group. |
| value_as_shown | STRING | Earlier source display text; keep it when interpreting zeros, dashes, and parentheses. |
| unit | STRING | Earlier measure unit: percent or thousand pesos. |
| footnote | STRING | Earlier source footnote text. |
| source_sheet | STRING | Earlier source sheet reference. |
| source_cell | STRING | Earlier source cell reference. Populated for 2021–2023; absent for 2024–2025. |
| source_name | STRING | Later source workbook name. |
| source_page | STRING | Later workbook page/sheet label: SUMMARY in 2024 and SUM in 2025. |
| source_row | STRING | Later source row reference; not a business identifier. |
| year | STRING | Fiscal year in the 2024–2025 layout. |
| category | STRING | Later source hierarchy/category label, including Grand Total. |
| budget_stage | STRING | Later budget stage such as Appropriations, Adjustments, Allotments, or Disbursements. |
| expense_class | STRING | Later expense class. Blank is expected for measures reported without class breakdown. |
| unit_amount | STRING | Later monetary unit: thousand pesos. |
| amount | STRING | Later monetary measure as extracted. Includes decimals, dash markers, and parenthesized negative amounts. |
| percent_type | STRING | Later rate label identifying the numerator/denominator relationship. |
| percent_amount | STRING | Later rate display text, such as 83.5% or #DIV/0!. This is separate from monetary amounts. |

## Ingestion columns

| Column | Type | Meaning |
|---|---|---|
| _rescued_data | STRING | Unexpected source fields captured during ingestion. Review nonblank values. |
| _drive_file_id | STRING | Google Drive source file ID. |
| _source_file | STRING | Relative path of the ingested CSV. |
| _landing_file | STRING | Landed source file path. |
| _source_modified_at | STRING | Source file modification timestamp as recorded by ingestion. |
| _source_sheet | STRING | Ingestion sheet selection; distinguish it from source_sheet/source_page business columns. |
| _content_hash | STRING | Source content fingerprint. |
| _header_map | STRING | Serialized source-to-normalized header mapping. |
| _dataset_hash | STRING | Dataset fingerprint recorded by ingestion. |
| _run_id | STRING | Ingestion run identifier. Shared by multiple records. |
| _ingested_at | TIMESTAMP | Timestamp when the record was ingested. |

## How to read the measures

- Amounts are in thousand pesos. Multiply by 1,000 only when converting to pesos.
- Parentheses mean negative: `(75,631)` is −75,631 thousand pesos.
- A dash stays a source marker until its meaning is verified for that field. Do not replace every dash with zero.
- Percentage text uses the 0–100 scale after removing the `%` symbol. `#DIV/0!` is a source formula-error marker, not 0%.
- PS, MOOE, FINEX, and CO are expense classes; Total is their reported aggregate.
- Keep source hierarchy. Adding agency rows, subtotals, and grand totals together would double-count amounts.
- The profiling views standardize labels for checking only. They do not change Bronze.

## Related files

- [Profiling SQL](profiling.sql)
- [Findings](findings.md)
