# Regional Appropriations Silver - Documentation

**Table:** `pondolens.dev_silver.regional_appropriations`

**Source:** `pondolens.dev_bronze.regional_appropriation` — DBM BESF regional allocation tables, GAA (Updated) basis.

**Grain:** one row per year, category, particular and region.

**Scope:** 2021–2025 detail records, including Nationwide and Central Office allocations.

**Documented by:** Razz

## Silver process

- Cleans text and numbers from Bronze.
- Gets standard region codes and names from `pondolens.dev_silver.shared_region_crosswalk`.
- Keeps 2021–2025 records and removes `ALL` particulars and `TOTAL` regions.
- Keeps Nationwide and Central Office as separate entries.
- Uses the latest loaded version of each record.
- Stops if records have invalid values, missing required fields, conflicting region matches or duplicate keys.
- Adds new records and updates changed values.
- Keeps existing IDs and records missing from a new batch.
- Removes previously loaded totals and records outside 202112025.
- Updates `processed_at` only when a record is added or changed.

## Silver treatments applied

- **Years:** keep only 2021-2025.
- **Totals:** remove `ALL` particulars and `TOTAL` regions to avoid double counting. Calculate totals by adding the appropriate detail rows.
- **Regions:** Use distinct region code and name pairs from `pondolens.dev_silver.shared_region_crosswalk`.
- **Nationwide and Central Office:** keep both entries. Their nonregional classification is stored and include them when calculating overall appropriation totals.
- **Text:** remove extra spaces at the start and end, and uppercase category and particular. Keep agency acronyms and meaningful punctuation.
- **Data types:** `gaa_id` and `year` are INT; `appropriation_amount` is DECIMAL(20,2); `processed_at` is TIMESTAMP.
- **Amounts:** multiply source amounts by 1,000 once to convert thousand pesos to pesos.
- **Dashes:** convert `-`, `–` and `—` to zero.
- **Missing values:** convert blanks and text `null` to NULL. Keep missing amounts as NULL. Stop if required fields are missing.
- **Repeated records:** use the latest `_ingested_at`. If tied, use the latest `_source_modified_at`. Keep one copy of identical records and stop if the latest records have different values.
- **Record IDs:** `gaa_id` identifies each year + category + particular + region_code combination. Existing combinations keep their IDs. New IDs start at 1000001 or continue after the highest existing ID.
- **Processing date:** `processed_at` shows when a record was added or last changed.
- **Source details:** keep the original source and loading information in Bronze.

## Silver table result

| Measure | Result |
|---|---|
| Rows | 4,256 |
| Regional coverage | 17 regions in the profiled source |
| Other entries | Nationwide and Central Office |
| Years | 5 (2021–2025) |
| Amount unit | Philippine pesos |

