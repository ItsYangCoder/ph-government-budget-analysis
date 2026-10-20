# Poverty Incidence — Data Profiling Notes

- **Table:** `pondolens.dev_bronze.poverty_incidence`
- **Source file:** `05_poverty_incidence_2021_2023_2025.xlsx` (PSA, Full Year Official Poverty Statistics)
- **Queries:** `poverty_incidence_profiling.sql`. Query numbers below (e.g. **Q2.1**) point to that file.

This notebook explains what we found in the raw (Bronze) poverty table, organized by the 7 profiling requirements, and what the Silver table should do about each finding.

| # | Requirement | Result |
|---|---|---|
| 1 | Dataset understanding | 644 rows, 2 sheets, 3 years, 5 geographic levels |
| 2 | Completeness | No missing numbers. Blanks only in `region_name` (MIMAROPA, PHILIPPINES), `province` (expected on region rows) and `notes` |
| 3 | Uniqueness | No exact duplicates and no repeated business keys |
| 4 | Validity | All rates 0–100. 8 zero estimates have `-` as CV. Many provinces need "use with caution" |
| 5 | Consistency | `region` and `region_name` are swapped for NCR, CAR, NIR and BARMM. Maguindanao was split in 2023 |
| 6 | Accuracy and reconciliation | National rate sits within the regional range for every year. Every regional rate sits within its provinces' range. Values match the Excel file |
| 7 | Silver treatment | Map to team region codes, cast numbers, turn note codes into TRUE/FALSE flags, keep 644 rows |

## Key terms (simple version)
- **Poverty threshold** — the minimum yearly income (per person) needed to buy basic food and non-food needs. Below this = poor.
- **Poverty incidence** — the percentage of people (or families) who are poor. Example: 10.9% means about 11 in every 100 families are poor.
- **Families vs population** — "families" counts households, "population" counts individual people. Poor families tend to be bigger, so the population rate is always higher.
- **Coefficient of variation (CV)** — how shaky the estimate is (aka margin of error in %). CV above 10% = "use with caution".
- **Standard error (SE)** and **confidence interval (CI)** — the range where the true value likely falls (95% sure). CI ≈ estimate ± 1.96 × SE.
- **pp (percentage points)** — the plain difference between two percentages. 15% vs 10% = 5 pp.

## 1. Dataset understanding (Q1.1 – Q1.6)

**Structure.** All 15 columns are stored as text (STRING), which is normal for Bronze. Numbers must be cast in Silver.

| Column | What it means | Example |
|---|---|---|
| `source_name` | Excel file name | 05_poverty_incidence_2021_2023_2025.xlsx |
| `source_page` | Sheet: `tab1` = families, `tab2` = population | tab1 |
| `source_row` | Row number in the Excel sheet (8 to 133) | 12 |
| `year` | Survey year: 2021, 2023, 2025 | 2025 |
| `region` | Region label (sometimes the long name, see section 5) | Region I |
| `region_name` | Second region label (sometimes the code, see section 5) | Ilocos Region |
| `province` | Province, district or city. Blank = the row is the whole region | Ilocos Norte |
| `annual_poverty_threshold_per_capita` | Poverty line in pesos per person per year | 36,000 |
| `reference_unit` | "Poverty incidence among families" or "…among population" | |
| `poverty_incidence_estimate` | The poverty rate in % | 10.9 |
| `poverty_incidence_coeff_var` | CV in %. `-` when the estimate is 0 | 4.5 |
| `poverty_incidence_standard_error` | SE in pp | 0.5 |
| `poverty_incidence_confidence_lower` / `_upper` | 95% CI bounds in % | 9.9 / 11.9 |
| `notes` | PSA footnote codes, comma-separated | 1/, b/ |

**Grain (what one row is).** One row = one **year × measure (families or population) × area**.
3 years × 2 measures × 107 areas, with 2 areas only in 2023/2025 → **644 rows**.

**Geographic levels (Q1.5).** There is no level column, so we derive it:

| Level | How we know | Rows |
|---|---|---|
| national | `region` = PHILIPPINES | 6 |
| region | province is blank | 108 |
| province | anything else | 494 |
| district | province ends with "District" (NCR districts) | 24 |
| city | province ends with "City" (Isabela City, Cotabato City) | 12 |

**Metadata.** One source file, two sheets (Q1.6). Query 8 (optional) checks pipeline lineage columns like `_run_id` and `_ingested_at`. Run it only if `DESCRIBE` shows those columns.

## 2. Completeness (Q2.1 – Q2.4)

**Missing values (Q2.1, Q2.2).**
- All numeric columns are filled. No missing estimates, thresholds, SE or CI.
- `region_name` is blank for **MIMAROPA (36 rows)** and **PHILIPPINES (6 rows)**. Silver fills it from the region mapping.
- `province` is blank on **114 rows**. This is expected: those are the national and regional total rows.
- `notes` is blank on **18 rows**. Fine, it just means no footnote applies.

**Years (Q2.3, Q2.4).** All areas have 2021, 2023 and 2025, except:
- **Maguindanao del Norte** and **Maguindanao del Sur** — only 2023 and 2025. Maguindanao was split into two provinces in 2022.
- The old **Maguindanao** row still exists for all three years, so 2023/2025 has both the combined province and its two parts. Do not add them together or count them twice (see section 7).

**Geographic coverage.** National + all 18 regions (including NIR and BARMM) + 81–83 provinces + 4 NCR districts + 2 cities per year per sheet.

## 3. Uniqueness (Q3.1 – Q3.3)
- **Exact duplicates (Q3.1):** none.
- **Business key (Q3.2):** `year + reference_unit + region + province` is unique. Use this as the Silver key.
- **Source position (Q3.3):** each sheet + Excel row + year appears once. Every row traces back to exactly one Excel cell.

**Expected result for all three:** no rows returned.

## 4. Validity (Q4.1 – Q4.8)

**Numeric values (Q4.2, Q4.3).**
- All estimates, SE and CI bounds convert cleanly to numbers.
- All rates are between 0 and 100. Every estimate is inside its own CI.
- The only non-number is `-` in the CV column, in **8 rows**.

**Zero estimates (Q4.4).** 8 rows (2025 provinces) have an estimate of **0** and CV `-`. CV is undefined when the estimate is 0 (you can't divide by zero). These rows carry the `c/` note. In Silver: CV = NULL, keep the 0.

**Estimate status: reliability (Q4.5).** CV above 10% means "use with caution".

| Level | CV ≤ 10 | CV > 10 | No CV |
|---|---|---|---|
| national | 6 | 0 | 0 |
| region | 104 | 4 | 0 |
| province | 194 | 292 | 8 |
| district | 2 | 22 | 0 |
| city | 4 | 8 | 0 |

National and regional numbers are solid. **Most province, district and city numbers are shaky**, so be careful when ranking provinces.

**Estimate status: note codes (Q4.6).**

| Code | Meaning | Rows |
|---|---|---|
| `1/` | Significant change 2021 → 2023 | 317 |
| `2/` | Significant change 2023 → 2025 | 500 |
| `b/` | CV above 10%, use with caution | 431 |
| `c/` | Estimate below 0.05% | 24 |
| `r1/` | Revised: Sulu moved from BARMM to Region IX | 12 |
| `r2/` | Revised: 63 North Cotabato barangays moved to BARMM | 18 |

**Important (Q4.7):** notes are set **per area, not per year**. If any of an area's 3 years has CV > 10, all 3 rows get `b/`. So `b/` on a single row does not mean that year's CV is above 10. For row-level reliability, use the CV number itself.

**Precision check (Q4.8).** CI ≈ estimate ± 1.96 × SE holds. The largest gap is about 0.19 pp, which comes from rounding.

## 5. Consistency (Q5.1 – Q5.6)

**Region names (Q5.1).** The two region columns follow different patterns:

| Pattern | Regions | `region` | `region_name` |
|---|---|---|---|
| Code, then name | Region I to XIII, IV-A | Region I | Ilocos Region |
| Name, then code (swapped) | NCR, CAR, NIR, BARMM | National Capital Region | NCR |
| Name only | MIMAROPA, PHILIPPINES | MIMAROPA Region | (blank) |

So neither column is consistently "the code" or "the name". **Don't use either one directly as the join key.** Map them with the team list (Q5.3).

**Spelling variants (Q5.2).** No names differ only by case or spacing. Expected: no rows.

**Codes (Q5.3).** Every `region` value maps to one team region code (PHL, NCR, CAR, I … XIII, IVA, IVB, NIR, BARMM). Expected: all MAPPED. These codes must match the ones in `dim_region` (Anje's).

**Geographic levels and boundary changes (Q5.4).**
- **NIR (Negros Island Region)** is included as a separate region for all years. Negros Occidental, Negros Oriental and Siquijor sit under NIR, not Region VI or VII. Other team datasets may still put them under VI/VII, so double-check before joining.
- **Sulu** is under **Region IX** for all years (revised, `r1/`). Older data places it under BARMM.
- **Cotabato** (`r2/`) figures were revised for the barangays moved to BARMM.
- **Maguindanao** split in 2023 (see section 2).

**Units (Q5.5, Q5.6).**
- tab1 is always families, tab2 is always population. Status: MATCH.
- The threshold is the same in both sheets for the same area and year. It's per person, so it doesn't depend on the measure.
- The family rate is never higher than the population rate (0 cases).
- Rates are in %, threshold in pesos per person per year.

## 6. Accuracy and reconciliation (Q6.1 – Q6.4)

**Why not just add up regions?** Poverty incidence is a percentage. Percentages cannot be summed (10% + 20% ≠ 30% national). Instead we check that the **national rate falls between the lowest and highest regional rate**. An average must always fall within that range.

**Regional vs national (Q6.1).** Status MATCH for all 6 year-measure combinations.

| Year | Measure | National | Lowest region | Highest region |
|---|---|---|---|---|
| 2021 | families | 13.2 | 2.2 | 26.1 |
| 2023 | families | 10.9 | 1.1 | 26.0 |
| 2025 | families | 6.4 | 0.6 | 16.8 |
| 2021 | population | 18.1 | 3.5 | 34.6 |
| 2023 | population | 15.5 | 1.8 | 35.2 |
| 2025 | population | 9.7 | 1.2 | 23.3 |

**Region vs its provinces (Q6.2).** Every regional rate falls between its lowest and highest province/district/city. 0 ISSUE rows.

**Regional gap (Q6.3).** Shows how many pp each region is above or below the national rate. NCR is the lowest every year. The highest is Region IX in 2021 (26.1%), BARMM in 2023 (26.0%) and Region V in 2025 (16.8%). This table is the basis for the "regional needs" side of PondoLens.

**Source file (Q6.4).** Q6.4 picks 10 random rows with their sheet and Excel row number, so you can open the Excel file and compare. I also compared every numeric value in the table with the Excel file: **4,508 values, 0 mismatches**.

## 7. Silver treatment (Q7.1 – Q7.3)

**Rules for the Silver table:**
1. **Cast types:** year → INT, threshold → DECIMAL(10,2), estimate, CV, SE, CI → DECIMAL(5,2).
2. **CV `-` → NULL.** Keep the 0 estimate.
3. **Region mapping:** replace `region` and `region_name` with the team `region_code` + one standard `region_name`. This fixes the swapped and blank labels.
4. **Add `measure`** (families / population) and **`geographic_level`** (national / region / province / district / city).
5. **`area_name`:** the province, district or city. For region rows, the region name.
6. **Note flags:** split `notes` into TRUE/FALSE columns: `sig_change_2021_2023`, `sig_change_2023_2025`, `use_with_caution`, `below_0_05_pct`, `revised_sulu_transfer`, `revised_north_cotabato_transfer`.
7. **`is_combined_area`** = TRUE for Maguindanao in 2023/2025, so charts don't double count it with del Norte and del Sur.
8. **Keep lineage:** `source_page` and `source_row`.
9. **Business key:** `year + measure + region_code + area_name`. Use MERGE on this key so reruns don't duplicate rows.

**Silver schema**

| Column | Type | Example |
|---|---|---|
| year | INT | 2025 |
| measure | STRING | families |
| geographic_level | STRING | region |
| region_code | STRING | I |
| region_name | STRING | Ilocos Region |
| area_name | STRING | Ilocos Region |
| poverty_threshold_php | DECIMAL(10,2) | 36000.00 |
| poverty_incidence_pct | DECIMAL(5,2) | 5.20 |
| coefficient_of_variation | DECIMAL(5,2) | 6.10 |
| standard_error | DECIMAL(5,2) | 0.32 |
| ci_lower_pct / ci_upper_pct | DECIMAL(5,2) | 4.57 / 5.83 |
| sig_change_…, use_with_caution, below_0_05_pct, revised_… | BOOLEAN | TRUE |
| is_combined_area | BOOLEAN | FALSE |
| source_page / source_row | STRING / INT | tab1 / 12 |

**Readiness check (Q7.2). Expected:** 644 rows, 0 duplicate keys, 0 unmapped regions, 0 missing estimates.

**For Gold (`fact_regional_indicator`):** use only `geographic_level = 'region'` and `measure = 'families'` (18 regions × 3 years = 54 rows). In `dim_indicator` it can be `indicator = 'poverty'`, `measure_type = 'poverty_incidence_families'`, `unit = '% of families'`. Keep the national row separately as the benchmark. Poverty data only exists for 2021, 2023 and 2025, so budget years 2022 and 2024 have no poverty value. Don't fill them in.
