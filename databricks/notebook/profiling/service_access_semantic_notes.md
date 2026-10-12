# Semantic Notes — `pondolens.dev_bronze.service_access`

**Purpose**: Document the *business meaning* of each data element — what indicators measure, why values are missing, how labels differ across sources, and what decisions govern harmonization. This complements the profiling notebook (which covers data quality) by answering "what does this data *mean*?"

**Source file**: `PH_service_access_2021_2025.csv` (single file, 400 rows)
**Bronze table**: `pondolens.dev_bronze.service_access`

---

## 1. Survey Cycle Semantics

### APIS–FIES alternation

The Annual Poverty Indicators Survey (APIS) is conducted by the Philippine Statistics Authority (PSA) in years when the Family Income and Expenditure Survey (FIES) is **not** conducted. This is the governing rule — APIS is not simply "biennial"; its schedule depends on FIES.

| Year | Survey conducted | APIS data available? |
| --- | --- | --- |
| 2021 | FIES | No APIS round |
| 2022 | APIS | Yes |
| 2023 | FIES | No APIS round |
| 2024 | APIS | Yes (published June 2025) |
| 2025 | FIES | No APIS round |
| 2026 | APIS | Expected (not yet released) |

### Implication for blanks

- **2021, 2023 blanks (80% blank)**: Structural — no APIS survey was conducted. These are not data errors or omissions; the survey simply did not run. Silver should tag these rows with `data_availability_reason = 'no_survey_round'`.
- **2025 blanks (100% blank)**: PSA ran FIES in 2025, not APIS. The next APIS will be 2026. **Do not backfill 2025** — there is no official 2025 APIS reference-year value. Retain as missing unless an official source publishes a comparable 2025 value.
- **2024 (0% blank)**: Fully populated. APIS 2024 data was published in the June 2025 WASH release. This is the most reliable and complete year.

### Non-APIS indicators

Not all indicators in this dataset come from APIS. Indicators sourced from WHO/UNICEF JMP, World Bank WDI, ITU, and PSA-DICT NICTHS follow their own publication schedules, not the APIS/FIES cycle. However, in this dataset the APIS-sourced rows (270 of 400) dominate and drive the blank-year pattern.

---

## 2. Indicator Definitions

### WASH indicators (source: PSA APIS)

| Indicator | What it measures | Unit / denominator | Notes |
| --- | --- | --- | --- |
| At least basic drinking-water access | % of families with access to at least basic drinking water | % of families | JMP ladder: improved source within 30 min round trip |
| Basic sanitation access | % of families using improved, unshared sanitation facilities | % of families | **Not** safely managed — PSA 2024 APIS lacked excreta treatment data. See §3 below. |
| At least basic sanitation access | % of families with at least basic sanitation | % of families | JMP "at least basic" = basic + safely managed. Only 15 rows — limited coverage in this dataset. |
| Basic handwashing facilities | % of families with basic handwashing facilities at home | % of families | |

### ICT indicators

| Indicator | What it measures | Unit / denominator | Source |
| --- | --- | --- | --- |
| Internet use, age 10+ | % of population aged 10+ who used the internet | % of population | PSA-DICT NICTHS |
| Internet access at home | % of households with internet access at home | % of households | PSA-DICT NICTHS |

**Note**: These two ICT indicators are the **only** ones with Residence (Rural/Urban) breakdowns. All other indicators use `breakdown_type = 'Total'` only.

### Energy indicators (source: World Bank WDI / Tracking SDG7)

| Indicator | What it measures | Unit / denominator | Source |
| --- | --- | --- | --- |
| Clean cooking access | % of population with access to clean cooking fuels | % of population | WHO/Tracking SDG7 via World Bank WDI |
| Electricity access | % of population with access to electricity | % of population | Tracking SDG7 via World Bank WDI |

---

## 3. Sanitation Ladder — Critical Semantic Distinction

The JMP sanitation service ladder has multiple rungs. Two appear in this dataset:

| JMP level | Definition | In this dataset? |
| --- | --- | --- |
| **Safely managed** | Improved facility, not shared, excreta safely disposed/treated | Not separately classified by PSA 2024 APIS |
| **Basic** | Improved facility, not shared (does not require safe waste management) | Yes — "Basic sanitation access" (90 rows) |
| **At least basic** | Basic + safely managed (combined upper rung) | Yes — "At least basic sanitation access" (15 rows) |

### Key decisions

1. **Do not merge or sum** the two sanitation indicators. They are distinct JMP ladder levels, not duplicates.
2. **Do not treat PSA's "basic sanitation" as "basic only"** in a mutually exclusive sense — PSA did not separately classify safely managed because information on excreta treatment was insufficient. The label covers improved, unshared facilities without establishing safe waste management status.
3. **Do not add a safely managed percentage** to PSA's basic figure to derive "at least basic."
4. **Keep the original PSA indicator labels** in Silver. Any harmonization with JMP terminology requires checking both definitions and denominators (see §5).

---

## 4. Region Semantics & Crosswalk

### Current region labels in `service_access`

18 regions: `National` (aggregate) + 17 regional. Labels are inconsistent:

- Most use full format: `Region I (Ilocos Region)`, `Region V (Bicol Region)`, etc.
- **Without full prefix**: `NCR`, `MIMAROPA`, `CAR` — these lack the "Region XIII", "Region IV-B", "Region XIII" style prefix.

### Crosswalk requirements

A single shared crosswalk should serve both `service_access` and `regional_expenditure_obligations` (and sibling tables). Structure:

| Column | Role |
| --- | --- |
| `source_region_label` | Original label from the source table (verbatim) |
| `region_code` | **Stable join key** — 2-digit analytical code (01–18, consistent across tables) |
| `standard_region_name` | Display label — full canonical name (e.g., `Region IV-B (MIMAROPA)`) |
| `boundary_version` | Tracks which geographic boundaries apply (pre-2022 vs post-2022 BARMM/CAR changes) |
| `applicable_years` | Years for which this mapping is valid |

### Key constraint

The obligations extraction uses **2-digit analytical region prefixes** (e.g., `01`, `13`), not full PSGC identifiers. This distinction must be preserved — a matching name or code alone does not guarantee matching boundaries.

**Rule**: Flag incompatible coverage rather than forcing a join. If a region's boundaries changed (e.g., BARMM creation, CAR redefinition), do not silently join across incompatible versions.

---

## 5. Denominator Semantics — Cross-Source Harmonization

Different sources measure the same concept using different denominators. **Never assume comparability without checking**:

| Concept | PSA APIS | WHO/UNICEF JMP | World Bank WDI |
| --- | --- | --- | --- |
| Sanitation access | % of **families** | % of **population** | % of **population** |
| Drinking water access | % of **families** | % of **population** | — |
| Electricity access | — | — | % of **population** |
| Internet use | % of **population** (via PSA-DICT NICTHS) | — | — |

### Harmonization rule

Before combining or comparing indicators across sources:
1. Confirm both use the same denominator (families vs population vs households).
2. Confirm both use the same definition (e.g., JMP "at least basic" vs PSA "basic").
3. If denominators differ, do not pool or average — flag the difference and document it.

---

## 6. Data Availability Taxonomy for Silver

Proposed `data_availability` classification for Silver rows:

| Classification | Condition | Rows affected |
| --- | --- | --- |
| `observed` | Non-blank `value` with a valid source | ~182 rows |
| `missing_no_survey_round` | Blank value, year is a FIES year (2021, 2023, 2025) | ~208 rows |
| `missing_future_release` | Blank value, year not yet surveyed (none currently beyond 2025) | 0 rows |
| `missing_other` | Blank value that does not match the above patterns | ~10 rows (investigate) |

The ~10 non-APIS blanks in 2022 and 2024 should be checked against their source publication schedules to confirm they follow a different structural pattern rather than being random gaps.

---

## 7. Source Provenance

| Source | Indicators | Rows | Publication body |
| --- | --- | --- | --- |
| PSA APIS | Drinking water, sanitation, handwashing | 270 | Philippine Statistics Authority |
| PSA-DICT NICTHS | Internet use, internet access at home | 50 | PSA / Department of ICT |
| WHO/UNICEF JMP (via World Bank WDI) | Drinking water, sanitation | 45 | WHO/UNICEF Joint Monitoring Programme |
| Tracking SDG7 (via World Bank WDI) | Clean cooking, electricity | 30 | World Bank / WHO |
| ITU (via World Bank WDI) | Internet use | 5 | International Telecommunication Union |

Each indicator maps to exactly one source. Source identity should be preserved in Silver with standardized source names for lineage.

---

## 8. Summary of Semantic Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | Tag 2021/2023 blanks as `missing_no_survey_round` | APIS not conducted in FIES years — structural, not error |
| 2 | Retain 2025 as missing; do not backfill | PSA ran FIES 2025, APIS 2026 — no 2025 APIS value exists |
| 3 | Keep both sanitation indicators; do not merge | Distinct JMP ladder levels with different definitions |
| 4 | Do not add safely managed % to PSA basic | PSA 2024 APIS did not classify safely managed separately |
| 5 | Preserve original PSA indicator labels | Harmonization requires denominator + definition check first |
| 6 | One shared region crosswalk; code as join key | Stable across tables; flag incompatible boundaries |
| 7 | Preserve 2-digit region prefix distinction for obligations | Obligations uses analytical prefixes, not full PSGC |
| 8 | Flag cross-source denominator differences | PSA = % of families; JMP/WDI = % of population |

---

*Last updated: Oct 12, 2026. Sources: psa.gov.ph, WHO/UNICEF JMP. Resolved questions sourced from user research and confirmed in conversation.*