# PondoLens Combined Dashboard — Data Lineage and Fixes

## Scope
Three Databricks AI/BI dashboard tabs: AP1 budget distribution, AP2 obligations relative to population, AP3 GRDP per capita relative to government obligations. The dashboard is a **definition**, not an exported data extract. Live data depends on the selected SQL warehouse, table access, and the presence of matching records.

## AP1 — Budget Distribution

| Dashboard dataset | Source tables | Metric / use |
|---|---|---|
| Budget_Overall | `pondolens.dev_gold.fact_regional_expenditure`, `dim_year`, `dim_location`, `dim_particular` | `appropriation_amount`; department/location filters, approved-budget charts and counters |
| Department Budget | Same four tables | Department appropriations; yearly top 3 departments vs. other departments, category `DEPARTMENTS` |
| Regional Budget | Same four tables | Regional appropriations and percentage share; denominator includes regional, Nationwide, and Central Office appropriations |

**Interpretation:** AP1 is approved **appropriations**, not actual cash disbursements. Regional percentages may not sum to 100% because the denominator includes Nationwide and Central Office.

## AP2 — Obligations Compared with Population

All AP2 widgets now calculate from Gold tables directly, with no dependency on the pre-existing `mv_population_spending_alignment` materialized view.

| Dashboard dataset | Gold sources | Used for |
|---|---|---|
| `ap2_regions` | `fact_regional_expenditure`, `fact_population`, `dim_location`, `dim_year`, `dim_particular`, `dim_age_group` | Obligations per resident and above/below national average bar chart |
| `ap2_headline` | Same six tables | National, lowest and highest obligations per resident; highest/lowest ratio; region labels |
| `AP2 Obligations and Population Share` | Same six tables | Population share vs. **obligations share** comparison table |

### AP2 calculations

- **Obligations:** `SUM(fact_regional_expenditure.obligation_amount)` for each region and year, excluding `dim_particular.category = 'UNKNOWN'` and null obligations.
- **Population:** `SUM(fact_population.population_count)` by region and year, using age groups from `dim_age_group`. The query excludes an age interval when it contains a strictly smaller age interval, to reduce overlapping group double-counting. **Validate this logic against your age-group values before publishing.**
- **Obligations per resident:** regional obligations / regional population.
- **National benchmark:** sum of *matched regional* obligations / sum of *matched regional* population, by year. This is not necessarily the national government total.
- **Population share (%):** region population / sum of matched regional population × 100.
- **Obligations share (%):** region obligations / sum of matched regional obligations × 100.
- **Share gap (percentage points):** obligations share − population share.
- **Above/below national average:** compares region obligations per resident with the matched-regions benchmark.

**Data scope:** only region-year records with both population and obligations and positive population are included. Nationwide and Central Office allocations are excluded from AP2 because they cannot be reliably attributed to residents of a specific region. This exclusion is analytical, not evidence that those funds did not benefit regions.

## AP3 — GRDP vs. Government Spending

| Dashboard dataset | Source | Used for |
|---|---|---|
| `mv_grdp_spending_population_without_ncr` | `pondolens.dev_gold.mv_grdp_spending_population_without_ncr` | GRDP per capita vs. obligations per resident scatter plot and median quadrant guides |
| `mv_grdp_spending_population` | `pondolens.dev_gold.mv_grdp_spending_population` | Included as an existing dataset; not used by the current AP3 scatter widget |

AP3 chart columns: `year`, `region_code`, `region_name`, `grdp_per_capita_php`, `obligations_per_resident_php`, `median_grdp`, `median_obligations`, `quadrant`. The displayed chart excludes NCR **by its materialized-view definition/name**; verify that the view actually does so. GRDP per capita is labeled at constant 2018 prices. **Inspect the underlying materialized-view SQL to verify the source indicator filtering, population calculation, and obligation exclusions.**

## Changes in this version

1. AP2 share table was changed from `pondolens.dev_gold.mv_population_spending_alignment` to a direct obligations-based SQL query using the same sources and year/region population matching as the AP2 benchmark charts.
2. Added `population_share_pct`, `spending_share_pct`, `share_gap_pp`, `spending_per_person_php`, and `region_code` to the AP2 regional query.
3. AP2 headlines and charts retain obligations (not appropriations) as the spending measure.
4. Removed a redundant `IN_RANGE(year, NULL, NULL)` query filter from the AP2 share table.
5. Replaced imported dashboard-specific query identifiers with local unique query names, updating their visualization references accordingly.

## If the dashboard still shows no data

Run these in Databricks SQL to isolate the issue:

```sql
SELECT COUNT(*) AS expenditure_rows,
       COUNT(obligation_amount) AS rows_with_obligations
FROM pondolens.dev_gold.fact_regional_expenditure;

SELECT COUNT(*) AS population_rows,
       COUNT(DISTINCT year_id) AS population_years
FROM pondolens.dev_gold.fact_population;

SELECT geographic_level, COUNT(*)
FROM pondolens.dev_gold.dim_location
GROUP BY geographic_level;

SELECT year, COUNT(*) AS rows
FROM pondolens.dev_gold.mv_grdp_spending_population_without_ncr
GROUP BY year ORDER BY year;
```

Open **Datasets** in the imported dashboard and preview `ap2_regions` and `AP2 Obligations and Population Share`. If both return zero rows, investigate region/year joins, overlapping age groups, missing population, or obligations data. If they return rows but the charts do not, check widget field mappings, year filters, and SQL warehouse permissions. Verify that each page's year filters select years that actually exist in its datasets.

**Validation limitation:** The JSON structure was edited and parsed locally; queries could not be executed against your Databricks workspace. Therefore a successful import or nonempty chart cannot be guaranteed without live validation.
