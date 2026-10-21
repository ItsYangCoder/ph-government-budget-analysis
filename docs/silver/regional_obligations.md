# Regional Obligations — Silver Documentation

Assigned to: Mia  
Updated: 21 October 2026 (Asia/Manila)  
Source: `pondolens.dev_bronze.regional_obligations`  
Reference: `pondolens.dev_silver.shared_region_crosswalk`  
Target: `pondolens.dev_silver.regional_obligations`  
SQL: `dbt/models/02_silver/regional_obligations/regional_obligations.sql`  
Scope: actual obligations, years 2021–2025

## Purpose and grain

Standardize DBM regional expenditure obligations (BESF Table B.6.a, *Regional Allocation of the Expenditure Program, Actual Obligations*) by year, category, agency or fund, and location.

One row represents **year × category × particular × region_code**. This combination is the natural key. `obligation_id` is the surrogate identifier.

Amounts are actual obligations: amounts agencies committed to pay, such as signed contracts or hired staff, whether or not they have been paid out. They are not appropriations (approved budget) and not disbursements (cash paid).

Only detail rows are stored. Source totals (`Total` column, `All` subtotals and `GRAND TOTAL`) are excluded because they can be recalculated with `SUM`.

## Output data dictionary

| Column | Type | Description |
|---|---|---|
| obligation_id | INT | Surrogate ID starting at 2,000,001; preserved for existing matched natural keys. |
| year | INT | Year of the obligation; current source covers 2021–2025. |
| category | STRING | DEPARTMENTS, SPECIAL PURPOSE FUNDS, or AUTOMATIC APPROPRIATIONS (2025 only). Kept as published. |
| particular | STRING | Agency or fund name, standardized for renamed offices. |
| region_code | STRING | Standard project code from the crosswalk, plus CO (Central Office) and NW (Nationwide). These are project codes, not official PSGC codes. |
| region_name | STRING | Standard uppercase name supplied by the crosswalk. |
| location_type | STRING | region, central_office, or nationwide. |
| expenditure_amount | DECIMAL(20,2) | Amount in pesos (source thousand pesos × 1,000); 0 for source `-` and blank. |
| value_status | STRING | Original amount classification: numeric, dash, or blank. |
| particular_as_stored | STRING | Agency or fund name exactly as received from Bronze, before standardization. |
| source_name | STRING | Source PDF file name. |
| source_page | INT | Source PDF page (1 or 2). |
| processing_run_id | STRING | ID of the run that last inserted or changed the record. |
| processed_at | TIMESTAMP | Timestamp of the run that last inserted or changed the record. |

`processing_run_id` and `processed_at` are the Silver audit fields. Original records and ingestion metadata remain in Bronze.

`value_status` and `particular_as_stored` preserve what the source showed and support data quality checks.

## Value statuses

| Status | Meaning |
|---|---|
| numeric | Valid non-negative amount, converted from thousand pesos to pesos. |
| dash | Source shows `-` (no amount); stored as 0. |
| blank | Source cell is empty; stored as 0. Occurs only in 2025 Automatic Appropriations. |
| invalid | Unrecognized text or failed decimal conversion; blocks the load. |

`-` and blank are stored as 0 because source totals reconcile only when they are treated as zero. The original marker is kept in `value_status`.

The invalid status may appear in staging but must not be loaded into the target.

## Location types

| Location type | region_code | Meaning |
|---|---|---|
| region | NCR, CAR, I–XIII, IVA, IVB, NIR, BARMM | Amount assigned to a specific region. |
| central_office | CO | Amount managed by an agency's head office for the whole agency. |
| nationwide | NW | Amount not yet distributed to a specific region. |

Central Office and Nationwide account for about 25–35% of total obligations each year. Exclude them for regional comparisons.

## Transformation rules

1. Trim text, collapse repeated spaces, and uppercase `category`.
2. Exclude source totals: `regions = 'Total'`, `particulars = 'All'`, and `category = 'GRAND TOTAL'`.
3. Keep the latest ingestion per year, category, particular, and region using `_ingested_at`. Ties are kept so conflicting values are caught by the duplicate check.
4. Classify amounts as numeric, dash, blank, or invalid. Convert numeric thousand pesos to pesos (× 1,000). Store dash and blank as 0.
5. Standardize renamed offices and funds using the name map below. Keep the original in `particular_as_stored`.
6. Normalize region labels into uppercase alphanumeric keys.
7. Resolve geography using the crosswalk:
   - Match on `source_region`, `region_code`, `region_name`, `REGION <code>`, or MIMAROPA variants.
   - The match must be valid for the observation year.
   - Block conflicting best matches.
8. Use the dataset-only fallback mapping for Table B.6.a labels when the crosswalk has no valid match. Take `region_name` from the crosswalk when the code exists there.
9. Classify CO as central_office, NW as nationwide, and other mapped locations as region.
10. Assign or preserve IDs and record `processing_run_id` and `processed_at` during loading.

### Agency name map

| Name in Bronze | Years | Standard name |
|---|---|---|
| The Presidential Communications Operations Office | 2021 | Presidential Communications Office (PCO) |
| Presidential Communications Operations Office | 2022 | Presidential Communications Office (PCO) |
| Office of the Press Secretary | 2023 | Presidential Communications Office (PCO) |
| Debt Service Fund-Interest Payment | 2021–2023 | Debt Interest Payments |

`dim_particular` uses the same map in uppercase. Tables joining to `dim_particular` must apply it before the lookup.

### Fallback region mapping

The fallback covers the 20 location labels used in Table B.6.a: Nationwide (NW), Central Office (CO), National Capital Region (NCR), Cordillera Administrative Region (CAR), Region I to XII, Region IVA, Region IVB, Negros Island Region (NIR), CARAGA (XIII), and BARMM.

It is applied only when the crosswalk has no valid match for that label and year. The shared crosswalk is not modified. To see which labels used the fallback in the last run:

```sql
SELECT * FROM regional_obligation_fallback_used;
```

Labels listed there should be reported to the crosswalk owner.

## IDs and load behavior

- The initial ID base is 2,000,000; the first assigned ID is 2,000,001.
- Existing matched natural keys retain their IDs.
- New keys receive IDs above the current target maximum, ordered by year, category, particular, and region_code.
- Sequential allocation requires one concurrent writer.
- ID gaps are expected (for example, after legacy subtotal rows were removed). IDs only need to be unique and stable.

| Source/target situation | Action |
|---|---|
| Natural key exists in both, values unchanged | No write; ID, processing_run_id and processed_at unchanged. |
| Natural key exists in both, values changed | Update attributes, processing_run_id and processed_at; preserve ID. |
| Natural key exists only in source | Insert with a newly allocated ID. |
| Existing record absent from the current source, for a year in the load | Delete, if 10% or fewer of that year scope's records are affected. |
| Existing record for a year not in the current load | Preserve. |
| Source location has no mapping or an amount is invalid | Fail validation before the data MERGE. |

An unchanged rerun writes no rows.

The script processes the current Bronze snapshot. It does not rely on an ingestion watermark.

## Target creation and schema upgrade

The SQL creates the schema and target table when absent. When upgrading an earlier table version, it adds these columns if they are missing:

- location_type
- value_status
- particular_as_stored
- source_name
- source_page

Before loading, the script also:

- Removes `All`, `GRAND TOTAL`, and `Total` rows kept by earlier versions.
- Renames old agency names already in Silver to their standard names, so those rows keep their IDs. It stops first if a rename would create a duplicate key.

Existing IDs and remaining columns are retained. Schema maintenance and the data MERGE are separate operations; a successful schema change may remain if a later statement fails.

## Validation gates

The SQL checks:

- No conflicting best crosswalk matches.
- No rejected rows: every row has a mapped region, valid year, expected category, particular, `Actual obligations` price basis, known unit, and valid non-negative amount.
- Preservation of row count after region mapping.
- Unique natural keys in staging and the existing target.
- Renaming legacy agency names does not create duplicate keys.
- Existing IDs are unique and greater than 2,000,000.
- No Bronze year has under 80% of its existing Silver rows (possible partial load).
- New IDs stay between 2,000,001 and 2,147,483,647.
- No more than 10% of in-scope Silver rows would be deleted.

Rejected rows and their reasons are available in `regional_obligation_rejected`:

```sql
SELECT rejection_reason, region_raw, year, COUNT(*) AS rows_rejected
FROM regional_obligation_rejected
GROUP BY ALL
ORDER BY ALL;
```

Source completeness and ingestion lineage quality must be checked upstream. Detailed source profiling and reconciliation are documented separately.

## Recorded validation results

The profiling of the long-format source shows:

| Check | Observed result |
|---|---:|
| Bronze rows | 4,345 |
| Detail rows loaded to Silver | 3,822 |
| Excluded total and subtotal rows | 523 |
| Unmapped rows | 0 |
| Numeric amounts | 2,489 |
| Dash amounts | 1,277 |
| Blank amounts | 56 |
| Invalid amounts | 0 |
| Duplicate natural keys | 0 |
| Location codes | 19 per year; 20 in 2025 (NIR) |

Source reconciliation (from profiling):

| Check | Groups | Match | Rounding (±1 thousand pesos) | Issue |
|---|---:|---:|---:|---:|
| Total column = Nationwide + Central Office + regions | 215 | 210 | 5 | 0 |
| Category subtotal = sum of agencies/funds | 223 | 223 | 0 | 0 |
| Grand total = sum of category subtotals | 101 | 98 | 3 | 0 |

The target output on 20 October 2026 contains:

| Year | Rows | Location codes | Regional rows | CO + NW rows | No-amount rows | Total (₱ trillion) |
|---|---:|---:|---:|---:|---:|---:|
| 2021 | 741 | 19 | 663 | 78 | 254 | 4.601 |
| 2022 | 760 | 19 | 680 | 80 | 262 | 5.175 |
| 2023 | 760 | 19 | 680 | 80 | 254 | 5.473 |
| 2024 | 741 | 19 | 663 | 78 | 262 | 6.273 |
| 2025 | 820 | 20 | 738 | 82 | 301 | 6.393 |

Each year's total equals the source PDF grand total. The first ID for 2021 is 2,000,021.

These results describe the 20 October 2026 snapshot. They are not fixed limits for future valid additions.

Rerun behavior, controlled updates, new-key insertion, and failure recovery require separate acceptance checks before unattended scheduling.

## Job execution

1. Run after successful Bronze ingestion and crosswalk maintenance.
2. Execute all SQL statements in order within the same session.
3. Stop execution on the first error.
4. Set Job maximum concurrent runs to 1.
5. Prevent overlapping ingestion, crosswalk changes, and other target writers during execution.
6. Check the final summary: row counts, location codes, and yearly totals against the source grand totals.
7. Retain validation outputs with Job run evidence.

Before scheduling, verify that:

- An unchanged rerun preserves IDs, row count, and totals.
- A corrected amount updates the existing record.
- A new natural key is inserted once.
- Invalid input blocks the merge.
- An incomplete Bronze load is blocked by the partial-load and deletion checks.

When a run fails, inspect the failed assertion, correct the responsible source or mapping, and rerun the complete script. Preserve existing target identifiers.

## Analytical limitations

- Regional amounts do not add up to the national total; Central Office and Nationwide are excluded from regional comparisons.
- NIR appears in 2025 only. In 2021–2024, Negros Occidental, Negros Oriental and Siquijor are counted under Region VI and VII, so those regions are not comparable before and after 2025.
- In 2025, DBM added the Automatic Appropriations category and moved Net Lending and Debt Interest Payments into it. Special Purpose Funds appear about 89% smaller in 2025 because of this reclassification, not a real cut. Use grand totals or DEPARTMENTS for year-to-year trends.
- Source amounts are rounded to the nearest thousand pesos; some source totals differ from the sum of their parts by 1 thousand pesos.
- Obligations can exceed GAA appropriations because of continuing appropriations, automatic appropriations, or transfers. Present such cases as needing verification, not as overspending.
- For per capita comparisons, use regional rows only and a consistent population year.
- Spending comparisons describe associations and do not establish causation.
- Source PDFs are scanned images; values were spot-checked during profiling, not compared cell by cell.

## Related files

- [Bronze profiling findings](../../profiling/bronze/regional_obligations/mia_regional_obligation_profiling_doc.md)
- [Bronze profiling SQL](../../profiling/bronze/regional_obligations/mia_regional_obligation_profiling.sql)
- [Regional obligations SQL](../../dbt/models/02_silver/regional_obligations/regional_obligations.sql)

Repository destination: `docs/silver/regional_obligations.md`.
