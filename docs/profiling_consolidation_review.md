Status: working draft. Rules marked PROPOSED are not final until the pending checks pass.

## 1. CONSOLIDATED FINDINGS

| Dataset | Finding | Proposed Silver treatment | Pending check |
|---|---|---|---|
| agency_actuals<br>[Mia’s notebook](https://github.com/ItsYangCoder/ph-government-budget-analysis/blob/2768bb00accf72ef86a768ab7df4d27954bd426a/databricks/notebook/profiling/mia_agency_actual_profiling.ipynb) | Reported: 809 dashes, 294 NULL amounts, 494 NULL expense classes, 70 NULL particulars and 12 failed rate parses. | **PROPOSED:** preserve structural NULLs and raw values; flag failed parses. | **PENDING:** inspect failed rates, dash meaning and structural NULL alignment. |
| agency_actuals | Reported: 98 rate records counted as missing monetary counterparts; 375 available pairs, 132 missing/unparsed and three candidate PHP 275 discrepancies. | **PROPOSED:** pair monetary records only; retain candidate discrepancies without summing them. | **PENDING:** rerun pairing; verify source values, hierarchy overlap, negative values, entity mapping and FY2025 cutoff. |
| agency_actuals | Reported: only 102 of 1,008 groups (10.12%) produced a class-total comparison. | **PROPOSED:** retain differences and classify uncomputed groups; NULL differences are not passes. | **PENDING:** establish eligible coverage and source rounding precision. |
| sector_expenditure<br>[Razz’s notebook](https://github.com/ItsYangCoder/ph-government-budget-analysis/blob/2768bb00accf72ef86a768ab7df4d27954bd426a/databricks/notebook/profiling/razz_sector_expenditure_profiling.ipynb) | Reported: 18 empty particulars; mixed stages and overlapping sector totals/details. | **PROPOSED:** preserve structural NULLs and all stages; classify row levels and retain parent sector for LGU subsidies. | **PENDING:** verify actual-year selection, source revision, denominator and total reconciliation. |
| regional_expenditure_gaa<br>[Anje’s notebook](https://github.com/ItsYangCoder/ph-government-budget-analysis/blob/2768bb00accf72ef86a768ab7df4d27954bd426a/databricks/notebook/profiling/anje_regional_expenditure_gaa_profiling.py) | Reported: 680 dashes; thousand-peso conversion wording is inconsistent. | **PROPOSED:** preserve labels; classify financial/geographic totals; apply candidate ×1,000 only after unit verification. | **PENDING:** source unit note, dash meaning, business keys and source reconciliation. |
| regional_expenditure_obligations<br>[Joy’s notebook](https://github.com/ItsYangCoder/ph-government-budget-analysis/blob/2768bb00accf72ef86a768ab7df4d27954bd426a/databricks/notebook/profiling/joy_regional_expenditure_obligations_profiling.ipynb) | Reported baseline: 1,785 rows; completed findings and confirmed unit: Not in source; mappings contain placeholders. | **PROPOSED:** configure actual schema and explicit row levels; withhold unverified conversion and totals. | **PENDING:** execute profiling; confirm unit, stage, cutoff and GAA scope. |
| population<br>[Rhea’s notebook](https://github.com/ItsYangCoder/ph-government-budget-analysis/blob/2768bb00accf72ef86a768ab7df4d27954bd426a/databricks/notebook/profiling/rhea_population_profiling.ipynb) | Reported: 17 regions; 1,295 sex differences of ±100, 589 age differences up to 400, and nine years with national differences up to 200 persons. | **PROPOSED:** preserve totals/differences; select July 1 projected Total/Both denominator; review differences above 100 as triage, not automatic failure. | **PENDING:** source explanations, age bounds, outlier distributions and boundary compatibility. |
| grdp<br>[Razz’s notebook](https://github.com/ItsYangCoder/ph-government-budget-analysis/blob/2768bb00accf72ef86a768ab7df4d27954bd426a/databricks/notebook/profiling/razz_grdp_&_grdp_per_capita_profiling.ipynb) | Reported: 18 regions; 12 missing region IDs; current and constant price bases. | **PROPOSED:** retain source IDs; map internal geography; keep price bases separate. | **PENDING:** MIMAROPA/national mapping, unit, configured worksheet and one-to-one comparison. |
| grdp_per_capita<br>[Razz’s notebook](https://github.com/ItsYangCoder/ph-government-budget-analysis/blob/2768bb00accf72ef86a768ab7df4d27954bd426a/databricks/notebook/profiling/razz_grdp_&_grdp_per_capita_profiling.ipynb) | Reported: 12 missing region IDs; existing decimal type has limited integer capacity. | **PROPOSED:** widen decimal type and preserve published per-person values. | **PENDING:** conversion precision, mapping, unit and geographic compatibility. |

## 2. COMMON SILVER RULES

- **Types — PROPOSED:** amounts `DECIMAL(38,12)`; percentages `DECIMAL(18,8)` on a 0–100 scale; counts `BIGINT`; years/numeric source positions `INT`; dates `DATE`; geographic keys `STRING`. Validate precision and arithmetic overflow; retain calculation precision and display amounts/rates to two decimals using HALF_UP.
- **NULLs and invalid values — PROPOSED:** zero stays zero; blanks → NULL; dashes → numeric NULL with raw text retained; structural NULL stays NULL. Use field-level `value_status`: `valid`, `missing`, `source_placeholder`, `not_applicable`, `invalid_numeric`, `valid_adjustment`, `review_required`. Failed parsing/precision/overflow retains the row with numeric NULL and a reason flag. Keep flagged rows in Silver; exclude unresolved inputs from affected metrics.
- **Units — PROPOSED:** validate against a unit lookup; PHP factor 1, thousand PHP ×1,000, million PHP ×1,000,000. Preserve original amount/unit and conversion factor; unknown/conflicting units block affected normalized metrics. Do not convert rates or persons into pesos.
- **Lineage — PROPOSED:** retain raw values, source name/path, row/page, revision, unit, Bronze ingestion time and flags; add Silver processing time. Preserve Bronze unchanged.

## 3. SEMANTIC NOTES AND BLOCKERS

No Databricks execution or source verification has been done yet.

- **PROPOSED — Utilization:** SUM(obligations) ÷ SUM(matching allotments) ×100.
- **PROPOSED — Unobligated allotments:** matching allotments − obligations.
- **PROPOSED — GAA–obligations gap:** comparable GAA − obligations; not unobligated allotments.
- **PROPOSED — Sector national share:** sector actual ÷ matching published actual grand total ×100, including applicable components outside four sectors.
- **PROPOSED — Spending per person:** comparable regional PHP amount ÷ matching projected population.
- **PROPOSED — YoY:** (current − prior) ÷ prior ×100 for the same measure/scope.
- **PROPOSED — Safe aggregation:** one non-overlapping hierarchy level, price basis and population denominator; no averaging rates or summing per-capita values. Use positive denominators; missing inputs → NULL with reason. Disclose exclusions and reconciliation coverage. Record actual differences; a theoretical rounding bound alone is not a pass.
- **PENDING — Geography:** verify a crosswalk or aggregate GRDP VI + VII + NIR against old-boundary population VI + VII, including matching spending geography and year-specific territory. **PROPOSED:** no proportional splitting or invented NIR population; publish only boundary-compatible comparisons.
- **PENDING — Publication blockers:** unresolved numeric inputs/units block affected amounts and rates; incomplete obligations profiling or unmatched stage/scope/cutoff blocks GAA comparisons; unresolved hierarchy/denominator/revision blocks totals and shares; incompatible boundaries block regional per-person metrics. **PROPOSED:** do not label incomplete totals as complete or publish overspending/underspending claims without an approved benchmark.

## 4. NEXT STEPS

| Priority | Owner | Action | Done when |
|---|---|---|---|
| P0 | Joy | **PENDING:** complete obligations configuration and profiling. | Actual schema, unit, cutoff, scope and findings recorded. |
| P0 | Mia, Razz, Anje, Joy, Rhea | **PENDING:** resolve unit, period and stage checks for owned datasets. | Source evidence supports each applicable mapping. |
| P0 | Rhea, Razz, Anje, Joy | **PENDING:** verify geographic crosswalk or combined-area option. | Matching territory/year and joins demonstrated without multiplied amounts. |
| P1 | Mia | **PENDING:** correct monetary pairing and investigate rates/discrepancies. | Revised statuses, source tie-outs and comparison coverage recorded. |
| P1 | Mia, Razz, Anje, Joy, Rhea | **PROPOSED:** implement/test common rules on owned datasets. | Precision, NULL, conversion, key and lineage checks pass; unresolved records flagged. |
| P1 | Mia, Razz, Anje, Joy, Rhea | **PENDING:** resolve owned hierarchy, denominator and reconciliation checks. | Safe row sets, actual differences, coverage and accepted tolerances documented. |
| P2 | Rhea | **PENDING:** PR review of this consolidation. | Findings, proposed rules and remaining blockers reviewed. |
