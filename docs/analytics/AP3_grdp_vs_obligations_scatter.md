# AP3 — GRDP per Capita vs. Government Obligations per Capita: Quadrant Scatter Plot

## Analytical problem
**AP3: How does regional government spending compare with GRDP per capita?**

## Visualization purpose
This scatter plot compares regional economic output per person with recorded government obligations per person. Median reference lines split the chart into four quadrants so policymakers can identify different combinations of relatively high/low economic output and relatively high/low obligations.

## Visualization design
- **Type:** Scatter plot with **uniform-sized points** (not a population-sized bubble chart).
- **Title:** Regional Economic Output vs. Government Obligations per Capita
- **X-axis:** GRDP per Capita (₱, Constant 2018 Prices)
- **Y-axis:** Government Obligations per Capita (₱)
- **Color:** `quadrant`
- **Tooltip:** Region code/name, actual GRDP per capita, actual obligations per capita, and yearly medians.
- **Filter:** Year (single selection).
- **Exclusion:** NCR is excluded from this focused visualization **and from its median calculations**; clearly disclose this in the subtitle.
- **Subtitle:** Regional comparison using annual medians; NCR excluded. GRDP in constant 2018 pesos and obligations in current pesos.

## Data sources (Gold layer)
| Table | Relevant columns | Purpose |
|---|---|---|
| `pondolens.dev_gold.fact_regional_indicator` | `year_id`, `location_id`, `indicator_id`, `measurement` | GRDP per capita values |
| `pondolens.dev_gold.dim_indicator` | `indicator_id`, `indicator`, `measure_type`, `unit` | Select constant-2018-price GRDP indicator |
| `pondolens.dev_gold.fact_regional_expenditure` | `year_id`, `location_id`, `obligation_amount` | Regional obligations |
| `pondolens.dev_gold.fact_population` | `year_id`, `location_id`, `age_group_id`, `population_count` | Regional population denominator |
| `pondolens.dev_gold.dim_location` | `location_id`, `location_code`, `location`, `geographic_level` | Region identity |
| `pondolens.dev_gold.dim_year` | `year_id`, `year` | Calendar year |

**Base SQL view:** `pondolens.dev_gold.mv_grdp_spending_population`.

Run [budget_vs_grdp.sql](../../analytics/q3_budget_and_indicators/budget_vs_grdp.sql) after the Gold build. It creates the base view and then the NCR-excluded view in order. Both are ordinary views despite their mv_ names.

**Selected GRDP indicator:**
- `indicator = 'grdp_per_capita'`
- `measure_type = 'grdp_per_capita_constant_2018_prices'`
- `indicator_id = 40003` (as observed in the current dimension)
- `unit = 'PHP/person (2018 prices)'`

The current-price GRDP measure (`indicator_id = 40002`) must **not** be mixed into this plot.

## Metric definitions
1. **GRDP per Capita (X):** The `measurement` associated with `grdp_per_capita_constant_2018_prices` for a given region and year.
2. **Total Obligations (₱):** Sum of `obligation_amount` by region/year.
3. **Regional Population:** Sum of `population_count` across non-overlapping age groups by region/year.
4. **Obligations per Capita (Y):** `total_obligations / total_population`.
5. **Median GRDP per Capita:** Median X across included regions **within the selected year**, excluding NCR.
6. **Median Obligations per Capita:** Median Y across included regions **within the selected year**, excluding NCR.

Both axes retain their **actual nonnegative monetary values**. The reference lines cross at **(median GRDP, median obligations)**, *not* at numerical (0, 0). Median lines change when the selected year changes.

## Quadrant definitions
| Quadrant | Position | Meaning |
|---|---|---|
| Q1 | Upper right | At/above median GRDP; at/above median obligations per capita |
| Q2 | Upper left | Below median GRDP; at/above median obligations per capita |
| Q3 | Lower left | Below median GRDP; below median obligations per capita |
| Q4 | Lower right | At/above median GRDP; below median obligations per capita |

For consistency, values **equal to** a median are assigned to the *high/at-or-above* side. Labels such as “high” and “low” mean **relative to the included regions' annual medians**, not absolute national standards.

## How the scatter plot answers AP3
The scatter plot shows whether regions with different levels of economic output per person also have different levels of recorded government obligations per resident. The four quadrants make these patterns easier to compare:

- **Q2** identifies regions with below-median GRDP per capita but at/above-median obligations per capita.
- **Q3** identifies regions with below-median GRDP per capita and below-median obligations per capita; these may warrant further investigation of needs and allocation priorities.
- **Q1 and Q4** show how obligations differ among regions with relatively higher economic output.

This answers AP3 **descriptively** by showing regional association and relative positioning. It does not demonstrate that government obligations cause GRDP to rise or fall, nor that an individual quadrant proves a funding mismatch.

## Databricks AI/BI configuration
| Setting | Field |
|---|---|
| Visualization | Scatter |
| X axis | `grdp_per_capita_php` |
| Y axis | `obligations_per_resident_php` |
| Color | `quadrant` |
| Size | Empty / uniform points |
| Tooltip | `region_code`, `region_name`, `median_grdp`, `median_obligations` |
| Year filter | Single year |
| Vertical annotation | Median GRDP value for the selected year |
| Horizontal annotation | Median obligations value for the selected year |

**Implementation caveat:** If Databricks AI/BI only supports constant numeric annotations, reference lines must be updated for each year or implemented with a supported dynamic alternative. Do not assume a fixed line automatically tracks the year filter.

## NCR exclusion and transparency
NCR was removed to reduce the visual impact of a high-GRDP outlier and make the other regions easier to distinguish. This exclusion is **not** a data-quality rejection. The chart and medians should both exclude NCR. Retain an all-region comparison as a supplementary visualization, and disclose the exclusion in the title/subtitle or methodology.

## Data quality and methodological checks
- Ensure exactly one GRDP measurement per region/year for the selected constant-price indicator; investigate duplicates rather than arbitrarily taking `MAX`.
- Aggregate population and obligations separately to region/year **before** joining.
- Confirm that the same region/year is available across GRDP, obligations, and population; flag missing matches.
- Verify the dashboard year filter selects a single year, preventing duplicate region points across years.
- Check the values and regional coverage used to compute each year's medians.
- Ensure zero or null population cannot produce division by zero.
- Review changes in geographic definitions across 2021–2025.

## Limitations
- GRDP per capita uses **constant 2018 prices**; obligations per capita use **current/nominal pesos**. They are not directly comparable as monetary amounts across years without inflation adjustment. The chart is most defensible for within-year regional comparison.
- Government obligations represent commitments, not necessarily completed disbursements or direct benefits to residents.
- Economic output per capita is not a complete measure of regional need or household well-being.
- Correlation or quadrant membership does not establish causality or budget sufficiency.
- Excluding NCR changes the comparison group and median thresholds; conclusions must be framed accordingly.

## Suggested dashboard caption
> This scatter plot compares regional GRDP per capita with government obligations per capita. Annual median lines divide the regions into four groups, highlighting where economic output and recorded obligations are relatively high or low. NCR is excluded to improve the readability of the remaining regions. Quadrant membership indicates relative positioning, not a judgment of budget adequacy.

## Recommended follow-up
Investigate regions in Q2 and Q3 alongside poverty, unemployment, education, health, sector-specific allocations, and budget execution before drawing policy conclusions.
