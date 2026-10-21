# AP2 — Regional Population vs. Government Obligations: Share Gap Table

## Analytical problem
**AP2: How does regional government spending compare to population?**

## Visualization purpose
This table compares each region's share of the population with its share of recorded government obligations in a selected year. It highlights regions whose share of obligations is above or below their population share and provides an obligations-per-capita measure for context.

## Visualization design
- **Type:** Table (Databricks AI/BI Dashboard)
- **Title:** Regional Population Share vs. Government Obligations Share
- **Grain:** One region per selected year
- **Filter:** Year (single selection)
- **Suggested columns:** Region (`region_code` / `region_name`), Total Population, Total Obligations (₱), Population Share (%), Obligations Share (%), Share Gap (percentage points), Obligations per Capita (₱).
- **Suggested sort:** Share Gap ascending to surface regions with the largest negative differences, or descending to surface the largest positive differences.
- **Formatting:** Two decimals for percentage measures; currency for peso amounts; conditional colors for negative/positive share gaps. Store numeric values separately from formatted display strings to preserve sorting.

## Data sources (Gold layer)
| Table | Relevant columns | Purpose |
|---|---|---|
| `pondolens.dev_gold.fact_population` | `year_id`, `location_id`, `age_group_id`, `population_count` | Regional population, summed across non-overlapping age groups |
| `pondolens.dev_gold.fact_regional_expenditure` | `year_id`, `location_id`, `obligation_amount` | Regional government obligations |
| `pondolens.dev_gold.dim_location` | `location_id`, `location_code`, `location`, `geographic_level` | Regional identifiers and names |
| `pondolens.dev_gold.dim_year` | `year_id`, `year` | Calendar year |

**Dashboard data source:** `pondolens.dev_gold.mv_population_spending_alignment` (verify that this is the view currently connected to the published table).

## Metric definitions
Let *r* denote a region and *y* a year.

1. **Total Population:** Sum of `population_count` over the non-overlapping age groups for region *r*, year *y*.
2. **Total Obligations (₱):** Sum of `obligation_amount` for region *r*, year *y*.
3. **Population Share (%):** `100 × region_population / sum_of_population_across_included_regions_in_year`.
4. **Obligations Share (%):** `100 × region_obligations / sum_of_obligations_across_included_regions_in_year`.
5. **Share Gap (percentage points):** `obligations_share_pct - population_share_pct`.
6. **Obligations per Capita (₱/person):** `region_obligations / region_population`.

The gap is measured in **percentage points**, not percent. For example, a population share of 10% and an obligations share of 8% yields a gap of **−2 percentage points**.

## How the table answers AP2
The table directly compares the regional distribution of government obligations against the distribution of residents. A **positive gap** means a region accounts for a greater share of obligations than its share of population; a **negative gap** means the reverse. Obligations per capita complements the gap by showing the recorded obligations relative to the number of residents. This allows budget holders to identify differences for further investigation, not automatically classify regions as overfunded or underfunded.

### Questions stakeholders can answer
- Which regions have the largest positive or negative obligation-share gaps?
- Which regions have relatively high or low obligations per resident?
- How do these differences change by year?
- Which regions merit follow-up analysis of need, program mix, and budget execution?

## Interpretation guide
| Observation | Appropriate interpretation | Avoid claiming |
|---|---|---|
| Positive share gap | Obligations share exceeds population share | Region is necessarily overfunded |
| Negative share gap | Obligations share falls below population share | Region is necessarily neglected |
| High obligations per capita | Higher obligations relative to residents | Every resident received that amount |
| Low obligations per capita | Lower obligations relative to residents | Spending is necessarily insufficient |

## Data quality and methodological checks
- Check that each population age group is non-overlapping and each region/year/age group appears once; otherwise population may be double-counted.
- Ensure obligations are aggregated to **region–year** before joining to population to avoid many-to-many multiplication.
- Use a consistent set of included regions for the population and obligations denominators; explicitly identify excluded national or central-office records.
- Verify that both shares sum to approximately **100% per year** over the included regions (rounding may introduce small differences).
- Verify the meaning of `obligation_value_status`, null handling, and any regional allocation limitations.
- Regions or years missing population or obligations should be flagged rather than silently interpreted as zero.
- Geographic boundary changes, including Negros Island Region, may affect year-to-year comparability.

## Limitations
- **Obligations** are budgetary commitments, not necessarily cash disbursements or benefits directly received by residents.
- Population is a broad measure of scale; it does not measure service demand, poverty, geography, costs, or sector-specific needs.
- A share gap is a **descriptive allocation comparison**, not an official funding-adequacy standard.
- Interpret changes across years cautiously if geographic coverage or reporting changes.

## Suggested dashboard caption
> This table compares each region's share of population with its share of government obligations. The difference, expressed in percentage points, identifies regions with relatively higher or lower recorded obligations compared with their population share. These differences are starting points for policy investigation rather than evidence of sufficient or insufficient funding.

## Recommended follow-up
Pair this table with sector-level allocation, regional development indicators, and budget execution data to investigate why a region's share differs from its population share.
