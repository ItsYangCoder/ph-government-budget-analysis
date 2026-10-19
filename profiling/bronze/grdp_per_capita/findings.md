# GRDP per Capita — Bronze Profiling Findings

Assigned to: Anje  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.grdp_per_capita`  
Reference: `pondolens.dev_silver.shared_region_crosswalk`  
Source label: `2018-2025 GRDP_Reg_(with NIR as of April 2026)`  
Scope: 2021–2025, with full-source coverage reviewed separately

## Purpose and grain

Assess completeness, numeric validity, uniqueness, and geographic compatibility before building Silver. One observation represents year, geography, price basis, and geographic level.

GRDP per capita measures economic output per person. It is not total GRDP, household income, or an amount that can be summed across regions to obtain a national value.

## Recorded results

These results come from Databricks outputs supplied by the owner on 20 October 2026. The accompanying profiling script includes additional checks whose results have not yet been supplied.

| Check | Recorded result |
|---|---:|
| Full Bronze rows | 296 |
| Table 2.1: current prices, full source | 152 |
| Table 2.2: constant 2018 prices, full source | 144 |
| Observations within 2021–2025 | 185 |
| Regional current-price observations in scope | 90 |
| Regional constant-price observations in scope | 90 |
| National current-price observations in scope | 5 |
| National constant-price observations in scope | 0 |
| Invalid year labels among the checked in-scope rows | 0 |
| Missing amounts in scope | 0 |
| Invalid numeric amounts in scope | 0 |
| Nonpositive amounts in scope | 0 |
| Amounts with fractional values in scope | 185 |
| Rescued rows in scope | 0 |
| Repeated source keys in the supplied check | 0 |
| Conflicting canonical names per code in the supplied check | 0 |
| Minimum amount in scope | 54,723.21816390364 |
| Maximum amount in scope | 631,279.0775186381 |

The source-key check grouped year, source region ID, price basis, and geographic level. It does not by itself establish uniqueness after canonical mapping or prove absence of all exact duplicates.

## Coverage by year

| Year | Regional constant | Regional current | National current | Total |
|---|---:|---:|---:|---:|
| 2021 | 18 | 18 | 1 | 37 |
| 2022 | 18 | 18 | 1 | 37 |
| 2023 | 18 | 18 | 1 | 37 |
| 2024 | 18 | 18 | 1 | 37 |
| 2025 | 18 | 18 | 1 | 37 |
| **Total** | **90** | **90** | **5** | **185** |

Missing national constant-price observations are a source-coverage difference, not evidence of ingestion failure. Do not create those observations by averaging regional per-capita values.

## Findings and proposed Silver treatments

| Finding | Proposed treatment |
|---|---|
| All business columns are STRING; `_ingested_at` is TIMESTAMP. | Preserve Bronze and assign validated analytical types in Silver. |
| Amounts are Philippine pesos per person. | Preserve the unit; do not multiply by 1,000. |
| All 185 in-scope measures have fractional values. | Propose DECIMAL(20,6) with explicit precision policy rather than automatic whole-peso rounding. |
| Philippines and MIMAROPA have blank source codes. | Resolve by normalized source/canonical names through the shared crosswalk. |
| IV-A uses a dash in the source code. | Resolve to canonical IVA through lookup normalization. |
| Crosswalk aliases include equivalent case and punctuation variants. | Deduplicate equivalent candidates and reject conflicting candidate mappings. |
| Source geographic level uses country. | Standardize Philippines to national with code PHL. |
| Two price bases are present. | Keep them as separate observations; use an explicit price-basis filter in analytics. |
| Bronze includes 2018–2020 outside the project period. | Profile them for context; filter the agreed 2021–2025 scope deliberately. |
| NIR has numeric history before the crosswalk validity interval. | Preserve Bronze observations and require a documented dataset-specific geographic decision before Silver temporal matching. |

## NIR and geographic comparability

The supplied source contains NIR values for both price bases from 2018 through 2025. The current shared crosswalk defines the NIR alias for 2024–2025.

Within the project scope, six NIR observations fall in 2021–2023: three years × two price bases. They can resolve to the canonical identity NIR while still requiring temporal review.

The workbook label “with NIR as of April 2026” suggests a revised geographic series. The label alone does not verify which historical boundaries were used. Confirm the original workbook notes and geographic revision methodology before approving a historical mapping exception. Do not extend the shared crosswalk dates simply to make a join pass.

Regional spending comparisons must separately assess NIR, Western Visayas, and Central Visayas boundary compatibility. Canonical code agreement alone is insufficient.

## Price basis and precision

Current-price and constant-price values answer different analytical questions. For the proposed 2021–2025 Silver representation, constant prices use price_basis = 2018 and current prices use price_basis = year.

If Silver later includes 2018, those numeric encodings collide for the two series. Add an explicit basis category before extending the scope to that year.

DECIMAL(20,6) is a proposed precision choice. It rounds to six decimal places and does not preserve every decimal digit of the source. Keep original measure strings in Bronze for traceability. The previously reviewed branch used BIGINT rounding; update its schema and transformation consistently if the decimal proposal is adopted.

## Pending checks

- Execute the complete attached profiling script and retain its outputs.
- Verify exact business-data duplicates and final canonical natural keys.
- Confirm every in-scope observation has exactly one canonical mapping.
- Review all crosswalk-period exceptions, including the six historical NIR observations.
- Check full-source year labels before filtering to avoid hiding malformed years.
- Check lineage completeness across the whole source, not just displayed sample records.
- Verify the original workbook's source authority, revision notes, and boundary methodology.
- Reconcile the extracted values to original source cells. No independent source-cell comparison has been supplied in this review.

## Readiness assessment

The supplied snapshot passes the reported in-scope amount, source-key, and rescued-data checks. Full Silver readiness remains conditional on mapping preview results, historical geography treatment, and an agreed numeric precision policy.

The accompanying SQL reads persistent tables and creates only temporary views. Its generated query results are not asserted to match the recorded baseline until executed in Databricks.

## Related files

- [Profiling SQL](profiling.sql)
- [Bronze data dictionary](data_dictionary.md)

Repository destination: `profiling/bronze/grdp_per_capita/`.
