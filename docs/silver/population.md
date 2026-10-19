# Population Silver - Documentation

**Table:** `pondolens.dev_silver.population`

**Source:** `pondolens.dev_bronze.population` — PSA 2020 Census-Based Population Projections, Table 1.

**Code notebook:** `razz_population_silver`

**Grain:** one row per region, year and age group, with sex = Both.

**Scope:** 17 regions × 5 years (2021–2025) × 18 age groups = **1,530 rows**.

**Documented by:** Razz

## Silver process

- Cleans text and numeric values from Bronze.
- Matches region labels to `pondolens.dev_silver.shared_region_crosswalk`.
- Keeps regional records for 2021-2025, Both sexes and the 18 age groups.
- Excludes Philippines and all-ages Total rows.
- Stops when rejected rows, conflicting mappings, duplicate mapped keys or invalid IDs are found.
- Checks if a year being loaded has fewer than 80% of its existing Silver rows.
- Inserts new records and updates changed region names, age limits or population values.
- Removes Silver records missing from the prepared data, but only for years being loaded.
- Updates `_processed_at` only when a record is inserted or changed.


## Silver treatments applied

- **Sex:** only Both is retained. Separate Male and Female rows are excluded.
- **Years:** only 2021–2025 are retained.
- **Total rows:** all-ages Total rows are excluded to avoid adding totals to their age-group breakdowns.
- **Regions:** codes and names come from the regional crosswalk table and are saved in uppercase. Matching ignores case, spaces and punctuation and accepts MIMAROPA / Region IV-B naming variations.
- **National records:** Philippines is excluded. Summing the regional records produces a derived national figure.
- **NIR:** no population values are created because NIR is absent from the source.
- **Data types:** `year`, `age_min` and `age_max` are INT; `population` is BIGINT.
- **Age labels:** labels are standardized, such as `0 - 4` and `85 and over`.
- **Missing values:** blanks, `null` text and dashes become NULL. Missing population values are never replaced with zero.
- **Age limits:** `age_max` remains NULL for `85 and over`.
- **Repeated records:** the latest ingestion is selected for each normalized Bronze key.
- **Added columns:** `population_id` identifies each record, and `_processed_at` records when it was inserted or changed.
- **Source rounding:** population figures are rounded to the nearest 100. Silver preserves the reported values, so age-group sums may differ slightly from published totals.

## Silver table result

| Measure | Result |
|---|---:|
| Rows | 1,530 |
| Regions | 17 |
| Years | 5 (2021–2025) |
| Age groups | 18 |
| Sex | Both |

## Region mapping

- Region codes and names use distinct pairs from `pondolens.dev_silver.shared_region_crosswalk`.
- Both region columns are stored in uppercase.
- Labels such as `REGION I (ILOCOS REGION)` are matched after normalizing case, spaces and punctuation.
- Accepted MIMAROPA labels include `MIMAROPA`, `MIMAROPA REGION`, `IV-B`, `REGION IV-B (MIMAROPA)` and `REGION IV-B (MIMAROPA REGION)`.
- The final code and name always come from the crosswalk.
- The DQ results show 17 distinct region codes, with all saved region pairs matching the crosswalk.
