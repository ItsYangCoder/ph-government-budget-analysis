%md
# Regional Appropriations Profiling - Documentation and Results

**Table:** `pondolens.dev_bronze.regional_appropriation`

- **Source basis:** Department of Budget and Management (DBM), Budget of Expenditures and Sources of Financing (BESF), regional allocation tables by department and special purpose fund, on a GAA (Updated) basis for 2021–2025.
- **Total Rows:** 4,780 rows.

**Description:** Government appropriations by year, category, department or fund, and geographical area.

**Grain:** year × category × particular × geographical area.

**Proposed Grain for Silver:** year × category × particular × region.

**Documented by:** Razz

## Assumptions and scope

- **Unit:** Amounts are reported in thousand Philippine pesos. Multiply by 1,000 to convert to pesos.
- **Silver scope:** Retain records only for 2021–2025.
- **Totals:** Exclude `TOTAL` regions and `ALL` particulars from Silver. Recalculate totals by summing the appropriate detail rows.
- **Geographic level:** Nationwide and Central Office are nonregional allocations. Retain their entries and include them when rebuilding overall appropriation totals.
- **Dash amounts:** Treat dashes as zero under the agreed accounting interpretation for this dataset.
- **Missing amounts:** Preserve missing amounts as NULL; do not replace them with zero.

## Data Profiling Findings

| Category | Finding |
|---|---|
| Dataset understanding | The table has 4,780 rows covering 2021–2025. |
| Dataset understanding | Each row represents an allocation by year, category, particular and geographical area. |
| Dataset understanding | Amounts are reported in thousand Philippine pesos on a GAA (Updated) basis. |
| Dataset understanding | All columns are STRING except `_ingested_at`, which is TIMESTAMP. |
| Dataset understanding | `ALL` particulars are aggregate rows; other particulars represent department or fund detail rows. |
| Completeness | No NULL values were found in the nine checked data columns. |
| Completeness | The data contains 17 regional labels, Nationwide, Central Office and Total: 20 geographical labels altogether. |
| Uniqueness | No duplicate records were found across the nine checked data columns. |
| Validity | There are 1,582 dash amounts: 204 in 2021, 333 in 2022, 365 in 2023, 344 in 2024 and 336 in 2025. |
| Consistency | Region labels mix codes and names, such as `Region IVA`, `CARAGA` and `National Capital Region`. |
| Consistency | Agency labels contain acronyms in parentheses. |
| Accuracy and reconciliation | All 239 geographical total comparisons returned MATCH with zero differences. |
| Accuracy and reconciliation | All 200 department and special purpose fund subtotal comparisons returned MATCH with zero differences. |
| Accuracy and reconciliation | All 100 grand total comparisons returned MATCH with zero differences. |

## Proposed Silver Columns and Treatments

| Column Name | Proposed Silver Type |
| :--- | :--- |
| `gaa_id` | integer |
| `year` | integer |
| `category` | string |
| `particular` | string |
| `region_code` | string |
| `region_name` | string |
| `appropriation_amount` | decimal(20,2) |
| `processed_at` | timestamp |

| Finding | Proposed Silver treatment |
|---|---|
| The data covers 2021–2025. | Retain records only within these years. |
| Published totals overlap with detail rows. | Exclude `TOTAL` regions and `ALL` particulars. Recalculate totals from the appropriate detail rows, including Nationwide and Central Office where applicable. |
| Region labels use different formats. | Match them to `pondolens.dev_silver.shared_region_crosswalk` and use its equivalent uppercase `region_code` and `region_name`. |
| Nationwide and Central Office are not individual regions. | Keep their entries and identify their nonregional geographic level in the region dimension. |
| Text labels need consistent formatting. | Trim and uppercase `category` and `particulars`; rename `particulars` to `particular`. Preserve agency acronyms and meaningful punctuation. |
| Year and amounts are strings. | Cast `year` to INT and `appropriation_amount` to DECIMAL(20,2). |
| Amounts are in thousand pesos. | Multiply by 1,000 once to store `appropriation_amount` in pesos. |
| Amounts contain dashes. | Convert dash amounts to zero. |
| Blank or missing values may occur in future batches. | Standardize blanks to NULL and preserve missing amounts as NULL. |
| Silver requires a record ID. | Assign a unique `gaa_id` to each new record. |
| New batches may introduce repeated records. | Remove identical cleaned rows and validate `year + category + particular + region_code` uniqueness. |
| Silver requires a processing timestamp. | Set `processed_at` when a row is inserted or changed. |
| Source details are needed for traceability. | Retain the original source and ingestion metadata in Bronze. |