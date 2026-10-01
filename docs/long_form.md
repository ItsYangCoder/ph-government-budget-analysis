# Data contracts and ingestion rules

## Conversion

Each source uses its own converter. Tables share fifty columns, with blank non-applicable dimensions. Important fields are `year`, `entity`, `measure`, `record_level`, `unit`, `value`, `value_php`, `value_status` and `analytical_eligible`.

Provenance includes source path/hash, source table/page/row/column, converter version, raw value and formula. Codes remain text to preserve leading zeroes. Monetary parsing uses `Decimal`; SQLite retains numeric representations as text. `value_php` applies only to supported monetary units.

| Source family | Output tables per file | Analytical rule |
|---|---|---|
| Agency actuals | Summary, detail candidates, numeric candidates | Select one reporting level and expense class; unresolved detail hierarchy stays excluded |
| GAA | Budget lines, controls | Exclude workbook SUM controls from budget totals |
| Sector | Sector expenditure, numeric candidates | Select nominal expenditure, actual status and sector level |
| Regional | Regional actuals | Exclude regional TOTAL and group/grand totals when summing detail |
| Population | Population projection, growth | Use one geography, age/sex selection and period; growth is not a population count |
| GRDP | Development indicator, numeric candidates | Select one price basis; per-capita values are not additive |

Two agency files produce six CSVs; two GAA files four; sector two; regional two; population two; GRDP two: eighteen CSVs from nine originals.

## Validation

Checks cover source coverage/hashes, expected business keys, value parsing and source-specific reconciliation. Duplicate observations remain available for investigation and block their source publication; they are not silently dropped.

Zero, blank, source dash and undefined rate are distinct. Source errors such as `#DIV/0!` remain traceable rather than being replaced with zero. Detailed tolerances, source exceptions and recorded results are in [validation evidence](evidence/long_form_validation.md); converter code defines executable checks.

Only PASS source partitions are loaded into SQLite. A source PASS does not establish that all original values are correct or that all retained rows can be summed together.

## Idempotency

The generation fingerprint covers source paths/hashes, converter code/version, configuration, extraction package versions and input mode; ZIP input also includes its hash. Reuse requires recorded output checksums to match. Changed or corrupted inputs/outputs trigger regeneration.

SQLite publication replaces the current passing-source snapshot in one transaction, including on a reused conversion. It does not append duplicate rows. A failed transaction rolls back. Failed/review-required sources have status records but no active data partition. A local exclusive lock prevents simultaneous runs.

## Query views

`validated_<dataset>` filters passing rows to analytical eligibility and parsed values, but reporting levels still need selection. Use narrower views where applicable:

| View | Selection |
|---|---|
| `agency_department_financials` | Department/fund reporting level, department section, TOTAL expense class |
| `sector_actual_financials` | Actual nominal sector expenditure |
| `regional_department_financials` | Department section, detail rows, excludes region TOTAL |
| `regional_population_totals` | Table 4, region, Both sexes, Total age |
| `regional_grdp_current_prices` | Regional per-capita GRDP, current prices |

Nationwide/Central Office spending categories do not have equivalent regional population denominators.

## Cross-source analysis

Before joins, review department/agency identities, hierarchy, fund coverage and geographic boundaries, including NIR/Sulu. Approved GAA, available appropriations, obligations and cash expenditure are distinct measures. Population data are projections; matching a year does not establish comparable geography.

No automatic cross-source join is published. Mapping application, local Silver/Gold and Databricks deployment remain future work. Planned Databricks landing uses files in a Unity Catalog Volume and managed Delta tables for analytical layers.
