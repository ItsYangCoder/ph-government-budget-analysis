# Regional Obligations — Silver

Documented by: **Mia Barroga**  
Updated: 22 October 2026 (Asia/Manila)  
Table: `pondolens.dev_silver.regional_obligations`  
Source: DBM BESF Table B.6.a, actual obligations

## Purpose

Stores government obligations by year, budget category, particular, and location. Obligations are financial commitments incurred; they are not cash payments or disbursements.

One row represents **one year + category + particular + region_code**. The reporting scope is 2021–2025. Regional records, Central Office, and Nationwide remain separate. Published totals and subtotals are excluded to avoid double counting.

## Data dictionary

| Column | Type | Meaning |
|---|---|---|
| obligation_id | INT | Record ID starting at 2,000,001. Existing business keys keep their IDs on rerun. |
| year | INT | Year of the reported obligations. |
| category | STRING | DEPARTMENTS, SPECIAL PURPOSE FUNDS, or AUTOMATIC APPROPRIATIONS, stored in uppercase. |
| particular | STRING | Standard agency or fund name. |
| region_code | STRING | Standard location code, including CO and NW. |
| region_name | STRING | Location name, stored in uppercase. Crosswalk names take priority over fallback names. |
| location_type | STRING | region, central_office, or nationwide. |
| expenditure_amount | DECIMAL(20,2) | Obligation amount in Philippine pesos. Dash and blank source amounts are stored as zero with a separate status. |
| value_status | STRING | numeric, dash, or blank. Invalid numeric text blocks the load. |
| particular_as_stored | STRING | Source particular label after trimming and whitespace cleanup, before approved name mapping. |
| source_name | STRING | Source document or file name. |
| source_page | INT | Parsed source page reference. |
| processing_run_id | STRING | Generated run identifier recorded when the row is inserted or updated. |
| processed_at | TIMESTAMP | Processing time recorded when the row is inserted or updated. |

The primary key is `obligation_id`. The business key is `(year, category, particular, region_code)`. SQL checks and dbt tests validate uniqueness.

## Transformation rules

- Trim text and normalize whitespace. Parse year and source page as integers.
- Exclude the Total location column, All subtotals, and GRAND TOTAL category.
- Keep the latest ingestion per source business key. Tied latest records remain subject to duplicate checks.
- Standardize Presidential Communications Operations Office and Office of the Press Secretary labels to Presidential Communications Office (PCO). Standardize Debt Service Fund-Interest Payment to Debt Interest Payments.
- Match normalized location labels against crosswalk aliases and validity years.
- When no year-valid match exists, use the model's explicit Table B.6.a fallback mapping. Prefer the crosswalk name for the fallback code when available. The shared crosswalk is not changed.
- Classify CO as central_office and NW as nationwide. Central Office is not assigned to NCR.
- Remove commas from numeric text. Convert thousand pesos to pesos by multiplying by 1,000; amounts already in pesos retain their scale. Parsing uses two decimal places before conversion.
- Store dash and blank amounts as zero while retaining their distinct value_status. This is the current Silver calculation rule; the status preserves the difference from a reported numeric zero.

## Quality checks

The SQL checks mapping ambiguity, supported categories, required particulars and locations, the actual obligations series label, accepted units, invalid numeric text, and negative amounts. Staged years must be between 2000 and 2100; the model does not restrict them to the reporting scope automatically.

Mapping must preserve the cleaned detail row count. Staged business keys, existing keys, and existing IDs must be unique. New IDs must fit the INT range.

Two guards check the main synchronization:
- A staged year below 80% of its existing Silver row count blocks the load.
- Deleting more than 10% of target rows across the staged years blocks the load.

The row-count guard does not detect a completely absent year or establish complete source coverage. The final SQL summary reports yearly counts, location coverage, statuses, and monetary totals; it does not assert reconciliation to the source publication.

[dbt tests](../../dbt/models/silver/schema.yml) check nonempty output, IDs, business-key uniqueness, and required attributes.

## Load and rerun behavior

The model creates the table when needed and adds five supported metadata columns when they are missing from an older target. It removes old totals and standardizes approved existing particular names while retaining their IDs. Rename collisions block the operation.

The main Delta MERGE keeps IDs for existing business keys, updates changed records, and inserts new keys after the current maximum. Rows absent from the source are deleted only for years present in the stage, subject to the deletion guard. Unchanged records retain their processing metadata.

Run through dbt after successful Bronze ingestion and crosswalk preparation, with **one concurrent writer**. Statements run in order; earlier schema changes, cleanup, or renames can remain if a later statement fails. Follow [pipeline recovery](../ingestion.md#pipeline-failures-and-recovery) before rerunning a failed load.

## Usage notes

- Amounts in this table are pesos. Confirm the same scale before combining them with appropriations.
- Filter location_type to region for regional population or indicator comparisons. Keep Central Office and Nationwide separate.
- Use value_status when distinguishing numeric zero from source dash or blank.
- Sum detail rows without adding published totals again.
- Compare matching years, locations, categories, and particulars. Matching codes alone do not confirm historical boundary compatibility.
- The model's expected count and total comments describe a source snapshot. Use actual run outputs for release evidence.

## Related files

- [Silver transformation SQL](../../dbt/models/silver/regional_obligations.sql)
- [Silver column definitions and dbt tests](../../dbt/models/silver/schema.yml)
- [Bronze profiling SQL](../../profiling/bronze/regional_obligation/profiling.sql)
- [Bronze data dictionary](../../profiling/bronze/regional_obligation/data_dictionary.md)
- [Bronze findings](../../profiling/bronze/regional_obligation/findings.md)
- [Shared region crosswalk](../shared_region_crosswalk.md)
- [Gold expenditure fact](../../dbt/models/gold/fact_regional_expenditure.sql)
