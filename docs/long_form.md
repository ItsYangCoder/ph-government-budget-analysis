# Long-form source tables

Every CSV uses an explicit schema. Blank non-applicable dimensions are retained. Financial values use `Decimal`, and SQLite stores the source representation as text. `value_php` normalizes only PHP/thousand-PHP/million-PHP monetary amounts; per-person indicators retain their own units in `value`.

Common fields include `year` or `period`, `entity`, `measure`, `record_level`, `status`, `unit`, `value`, `value_php`, `value_status`, and `analytical_eligible`. Trace fields include source filename/hash, converter version, source table/page/row/column, raw value and original formula. PDF row coordinates are the y position rather than an invented Excel row number.

| Dataset | Record key/grain | Selection for analysis |
|---|---|---|
| `approved_budget` | Year, department, agency, program/code/level, operating unit, region, division, fund, expense, subobject | Budget lines. Keep agency-specific funds and automatic appropriations distinct |
| `approved_budget_controls` | Year, control row | Reconciliation only; final workbook SUM is not another budget line |
| `agency_summary` | Year, entity, row role, section, measure, expense class | Choose department rows and one expense reporting level |
| `agency_detail_candidates` | Year, sheet, row, column | Original wide measures melted; hierarchy not yet resolved, so excluded from analytical views |
| `sector_expenditure` | Measure, year/end year, sector/subsector and parent | Choose nominal expenditure, sector level and actual status for cash-based sector trends |
| `regional_actuals` | Year, department/SPF, region | Choose department detail; exclude TOTAL and group/grand totals when summing region detail |
| `population_projection` | Source table, year, geography/parents, age, sex | Table 4 regional totals, Both sexes, Total age; projected mid-year values |
| `population_growth` | Geography and interval | Projected average annual growth; not population counts |
| `development_indicator` | Year/end year, region, measure and price basis | Per-capita GRDP at one price basis; do not sum per-capita values |
| `source_numeric_candidates` | Source, sheet, row, column | Retained numeric headers/support/unlabelled cells; excluded from analytics |

Source program headings without a GAA amount are not financial records. They remain in the original workbook and structural extraction. GAA dimensional codes are preserved as text; leading zeroes are not removed. No department/agency names are fuzzy-matched automatically.

## Value states

- `ok`: parsed numeric source value, including an actual zero.
- `source_dash`: the source printed a dash; the stored value stays empty.
- `missing`: the source value was blank; it stays distinct from a dash and numeric zero.
- `undefined_rate`: the agency source contains `#DIV/0!` in a rate column; the raw error is retained and not changed to zero.
- `source_excel_error`, `missing_formula_cache`, `invalid_numeric`, `invalid_domain`: retained review states. Invalid analytical values block their source publication. Population counts must be nonnegative integers.

PDF blanks/dashes are treated as zero only inside printed-total reconciliation, where the omitted cells are explicit source states. They do not become fabricated numeric observations. Raw text retains all original tokens. Regional word fragments are joined before column assignment, and every column caption is checked.

## Controls

1. Validate expected source folders/counts, distinct FY2024/FY2025 files, source hashes and ZIP record provenance.
2. Check exact business keys. Duplicate rows remain in CSV and block publication; do not silently delete them.
3. Reconcile agency expense-class totals, available appropriation arithmetic, balance arithmetic, and department-to-NGA summary totals. Source rates remain separately identifiable.
4. Reconcile GAA budget-line sums against its workbook SUM, excluding that SUM from budget lines. For the two known hashes, verify Senate fund `01101101` against official GAA appropriations and confirm thousand-peso units.
5. Reconcile nominal sector totals. Seven sections remain separate: expenditure, share, growth, GDP share, per capita, real levels, and real growth. Growth interval headers map to end year and preserve their interval.
6. Reconcile regional amounts across both pages, details to department/SPF groups, and groups to grand totals.
7. Reconcile population male/female counts with both sexes and cross-check regional/country total population between Tables 1 and 4.
8. Recalculate GRDP growth and national index values from their corresponding per-capita series. The source's Table 2.6 C183 header says `Annual`; its 2023 mapping follows the explicit 2023–2025 series title and adjacent years, and is documented in the report.

Tolerances are expressed in the source unit, not silently in pesos: agency arithmetic 0.001 thousand PHP; six-sector totals 3 million PHP for rounded historical source totals; PDF across-region row totals 11 thousand PHP, group detail totals 25 thousand PHP, and group-to-grand totals 3 thousand PHP; population sex totals 100 persons (source rounding), Table 1/Table 4 comparison exact; GRDP formula checks 0.000001; GAA and official Senate amount controls exact. These checks detect conversion/reconciliation issues, not all possible errors in the publisher's original data.

## Safe SQL views

`validated_<dataset>` views contain passing-source rows with a mapped numeric value. They still contain explicit reporting levels; never sum all their rows without selecting the grain.

Use the narrower views where appropriate:

- `agency_department_financials`: department reporting level, expense class TOTAL.
- `sector_actual_financials`: actual nominal sector totals, excludes subsectors and grand totals.
- `regional_department_financials`: department detail, excludes TOTAL and subtotals. Nationwide/Central Office remain for reconciliation and must be excluded from population denominators.
- `regional_population_totals`: Table 4 regional total age and both sexes.
- `regional_grdp_current_prices`: region-level per-capita GRDP at current prices.

## Idempotency and publication

A generation fingerprint includes source-relative paths and SHA-256 hashes, converter code, explicit version, configuration, installed extraction package versions, input mode, and the extraction ZIP hash when applicable. Reuse requires all recorded output checksums to match. Changes or corruption rebuild the generation; completed older source generations remain available.

SQLite publication runs inside one transaction and replaces the current passing source snapshot. It does not append the same rows on a rerun. A duplicate/failed/review-required source is absent from the current data tables and has an explicit status record. Database contents are rebuilt even when CSV conversion is reused, repairing missing rows. A failed publication transaction rolls back the snapshot.

An exclusive lock prevents simultaneous local runs. If the process is killed, remove `outputs/.long_form.lock` only after confirming that no ingestion process remains active. CSV/report writes are staged before publication. This is a local single-process pipeline; it does not claim distributed locking or Databricks MERGE semantics.

## Cross-source gates

Source conversion PASS is separate from `ready_for_cross_source_analysis`:

- Review agency/department code and name mappings across GAA and SAOB.
- Align fund scope: available appropriations include adjustments/continuing/automatic funding and are not equivalent to approved agency-specific GAA.
- Resolve detailed agency hierarchy before combining SUCs/agency/department rows.
- Review NIR/Sulu and other geographic boundaries across regional spending, population and GRDP; year alone does not make boundaries comparable.
- Keep obligations and cash expenditure separate and explain their meanings in the analytical model.

No automatic cross-source financial or geographic join is published by this command.
