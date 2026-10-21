# Regional Obligations — Bronze Findings

Assigned to: Mia Barroga
Documented by: Mia Barroga
Table: `pondolens.dev_bronze.regional_obligations`

## Evidence and execution status

The previous findings file in this folder described Poverty Incidence, not Regional Obligations. It is retained under `docs/archive/profiling/misfiled_poverty_findings.md` for historical reference and is not evidence for this dataset.

No result set for the revised complete profiling SQL has been captured in this consolidation. All revised checks require a Databricks run. Do not copy poverty counts, missing-marker meanings, or statistical rules into this dataset.

## Dataset and grain

A source observation is a reported amount by year, category, particular, source location, series label (`price_basis`), and unit. Published totals and category subtotals overlap detail rows. Preserve source file/page to trace observations and distinguish publication revisions.

`year + category + particulars + regions + price_basis + unit_amount` is a candidate key, not a verified uniqueness guarantee. The duplicate query retains conflicting or repeated source observations for review.

## Treatment boundaries

- Keep source strings and ingestion metadata unchanged in Bronze.
- Profiling parses accounting parentheses as negative amounts; a negative value is reported for review, not automatically rejected or converted to positive.
- Dashes, en dashes, and em dashes are source markers. Missing and invalid numeric values remain unresolved; this profiling SQL does not convert them to zero.
- No currency conversion is performed. Confirm the actual unit before applying any downstream factor.
- `price_basis` is a source series label here, not automatically a constant-price year.
- Central Office and Nationwide remain distinct from regional amounts. Central Office is not automatically NCR.
- Resolve geography using distinct canonical crosswalk pairs and applicable years. Do not change shared crosswalk validity to make a profiling join pass.
- Reconciliation reports component counts, duplicate locations and unresolved values. Only complete, numeric, unique groups receive MATCH/DIFFERENCE; exact MATCH alone does not prove all expected regions are present.
- Do not sum totals and detail records together or silently deduplicate across revisions.

## Checks to complete

1. Run schema, coverage, source-aware duplicates, marker, numeric range, and lineage queries.
2. Review every location/year with mapping count other than one, except the separate Total aggregate.
3. Verify publication edition, reference period, unit, series and dash meanings against source notes.
4. Reconcile geographical totals, then confirm category/grand totals and expected component sets against the source hierarchy. The script covers geographical, category and grand-total reconciliation; expected component sets and hierarchy acceptance remain source review tasks.
5. Confirm post-mapping detail-key uniqueness and currency precision in Silver separately.

## Related files

- [Profiling SQL](profiling.sql)
- [Data dictionary](data_dictionary.md)
- [Profiling runbook](../../README.md)
