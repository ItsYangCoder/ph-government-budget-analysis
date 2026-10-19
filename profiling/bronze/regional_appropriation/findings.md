# Regional GAA Profiling
Owner: Anje
Table: `pondolens.dev_bronze.regional_appropriation`
Baseline: 4,780 rows

**Goal:** profile regional appropriations for Q1/Q2 and assess compatibility with indicators for Q3. All queries are read-only.

**Row meaning:** A government expenditure allocation for a specific fiscal year, expenditure category, particular (department or special purpose fund), and geographical area.

## Checks
- Check counts by file/year, column types, and nulls/blanks.
- Define what one row represents; check exact duplicates and repeated business keys.
- Verify regions, years, categories, particulars, numeric amounts, units, and price basis.
- Identify totals/subtotals to avoid double counting.
- Compare sample amounts and totals with the original source.
- With Joy, check whether GAA and obligations have matching scope, periods, and regions.
- Check regional compatibility with population and GRDP.

## Findings
| Check / Issue | Affected rows / Evidence | Proposed Silver treatment |
|---|---|---|
| Dashes in expenditure_amount column| 336 rows in 2025 table, 344 rows in 2024 table| Pending source verification; preserve the raw marker and do not assume zero.|
| Special characters in particulars column (). The data contains both the department and the acronym of the department inside the () | 40 distinct column_value with 20 occurences each for both 2024 and 2025 tables. 39 of these values are the agency names while the other value is GAA(updated)| Separate the acronym from the full agency names|
| when particulars = 'All', these are aggregate rows. Other particulars are department or fund detail rows rathen than automatically being subtotals | All rows| Keep all rows in Silver and add two classification columns. This preserves published totals for validation while allowing dashboards to select detail rows without double counting. financial_row_type: grand_total, category_total, detail AND geographic_row_type: geographic_total, nonregional, regional|
|Expenditure amount in thousand pesos|all rows| Retain the documented thousand-peso unit. Convert only after confirming the required target unit; avoid applying the scale twice.|

## Assumptions to Verify
| Question | Status |
|---|---|
|Dashes have a value of zero|to verify with team|
|Should we convert all Region-IVA to RegionIVA|to verify with team|

## Semantic Notes
- The amount is expressed in thousand Philippine pesos (₱'000).
- 'All' is an aggregate label; classify its meaning with category and geographic scope before aggregation.
- 'Total' represents the sum of applicable geographical allocations


## Conclusion
- Proposed Silver changes: standardize geographic labels, classify aggregate/detail rows, preserve source units, and retain agency labels/acronyms. Dash-to-zero interpretation and any unit conversion remain pending verification.
- Analytical readiness: pending verification of dash semantics, aggregate/detail classification, amount units, and geographic compatibility. Profiling results alone do not establish readiness. 
- Open questions: How do we treat Nationawide and Central Office allocations?

## 1. Structure and coverage
Inspect columns, sample records, years, and geographic labels. PHILIPPINES is a national total, not a region.

## 2. Data quality
Check required values, numeric/date parsing, rescued data, and repeated candidate keys. Empty duplicate results mean no repeated keys were found.

## 3. Reconcile totals
- Geographical reconciliation: Does the sum of all regional amounts, Nationwide, and Central Office equal the reported Total?
- Particulars reconciliation: Does the sum of individual departments or special purpose funds equal the corresponding All subtotal?
- Grand total reconciliation: Does DEPARTMENTS + SPECIAL PURPOSE FUNDS equal GRAND TOTAL?

## Review notes

The SQL now references the renamed Bronze table `regional_appropriation`. Reported findings are retained from the author's profiling; these queries have not been independently executed during repository review. Reconciliation queries use TRY_CAST, so invalid numeric tokens must be investigated separately before treating a matching total as evidence of correctness.
