# Population Profiling - Documentation and Results
**Table:** `pondolens.dev_bronze.population`

- **Source basis:** Projected Mid-Year Population (1 July), by region, sex and five-year age group, 2020–2035 - PSA 2020 Census-Based Population Projections, Table 1.
- **Total Rows:** 16416 rows

**Description:** PSA population projections by region, age group and sex.

**Goal:** identify cleaning needed before Silver and assess regional totals for Q3.

**Grain:** region × year × age group × sex.

**Proposed Grain for Silver:** region x year x age group

**Documented by:** Razz


## Assumptions and scope

- **Source:** PSA’s 2020 Census-Based Population Projections, Table 1, provides projected mid-year population as of 1 July by region, sex and age group. Since censuses are not conducted annually, this dataset uses projections for yearly comparisons, including 2025, rather than directly counted census populations for each year.
- **Unit:** Population is measured in persons.
- **Silver scope:** Only records for 2021-2025 will be processed.
- **Totals:** TOTAL covers all ages, and BOTH covers both sexes. Do not add these totals to their breakdowns.
- **Missing age limits:** NULL age limits are expected for TOTAL and the upper limit of 85 and over.
- **Missing population:** Missing values must not be treated as zero.
- **NIR:** No population values will be created for NIR because it is not inside the source.
- **National aggregation:** The sum of regional records becomes a calculated national total and may differ from the source-reported Philippines value.

## Data Profiling Findings

| Category | Finding |
|---|---|
| Dataset understanding | Bronze contains 16,416 rows covering 2020–2035. |
| Dataset understanding | Only records for 2021–2025 should be processed into Silver. |
| Dataset understanding | Values represent projected mid-year population as of 1 July. |
| Dataset understanding | The source is PSA’s 2020 Census-Based Population Projections, Table 1. |
| Dataset understanding | Each record represents region × year × age group × sex. |
| Dataset understanding | All columns are STRING except `_ingested_at`, which is TIMESTAMP. |
| Dataset understanding | Source and ingestion metadata are available. |
| Dataset understanding | Philippines is the separately reported national total covering the 17 regions, not an additional region. |
| Completeness | No missing region, year, population, age group, sex, reference date or source values were found. |
| Completeness | The 864 missing age_min values correspond to TOTAL records. |
| Completeness | The 1,728 missing age_max values correspond to TOTAL and 85-and-over records. |
| Completeness | Coverage includes 17 regions and Philippines. |
| Completeness | NIR is absent from the source. |
| Completeness | There are 85 regional TOTAL/BOTH records for 2021–2025. |
| Uniqueness | No exact duplicates were found, with or without ingestion metadata. |
| Uniqueness | No repeated region/year/age-group/sex keys were found. |
| Validity | No invalid numeric values were found in year, age_min, age_max or population. |
| Validity | No dash placeholders were found in year, age_min, age_max or population. |
| Validity | No negative values were found in year, age_min, age_max or population. |
| Validity | All populated values in the checked numeric fields represent whole numbers. |
| Validity | Population ranges from 2,100 to 123,963,500 across Bronze. |
| Validity | No zero population values were found. |
| Validity | An age_min of zero is valid for the 0–4 age group. |
| Validity | No invalid years or reference dates were found. |
| Validity | All reference dates agree with their year values. |
| Validity | No unexpected sex values or age-group labels were found. |
| Validity | `_rescued_data` is null throughout. |
| Consistency | Region labels contain prefixes, parentheses and inconsistent capitalization. |
| Consistency | Region codes are not stored in a separate column. |
| Consistency | Population values are counts of persons. |
| Accuracy and reconciliation | All 16,416 CSV population values match original Excel File.. |
| Accuracy and reconciliation | All CSV reference dates match the original Excel. |
| Accuracy and reconciliation | No source records are missing from the CSV. |
| Accuracy and reconciliation | The sum of the 17 regional TOTAL/BOTH values matches Philippines in 2021 and 2025. |
| Accuracy and reconciliation | The regional sum is 100 higher than Philippines in each of 2022, 2023 and 2024. |
| Accuracy and reconciliation | These differences also appear in the original Excel and were preserved during ingestion. |

## Proposed Silver Columns and Treatments

| Column Name | Proposed Silver Type |
| :--- | :--- |
| `region_name` | string |
| `age_group` | string |
| `age_min` | integer |
| `age_max` | integer |
| `sex` | string |
| `year` | integer |
| `population` | bigint |
| `_processed_at` | timestamp |

| Finding | Proposed Silver treatment |
|---|---|
| Bronze covers 2020–2035. | Retain only records for 2021–2025 in Silver. |
| Region labels need standardization. | Transform each label into its respective standardized region_name and region_code, following the agreed mapping. |
| Year and age limits are stored as strings. | Cast year, age_min and age_max to INT. |
| Population is stored as a string. | Cast population to BIGINT. |
| Age-group and sex labels require consistent formatting. | Trim and standardize age_group and sex as STRING values. |
| Missing age limits are expected for TOTAL and 85 and over. | Preserve these NULL values. |
| Blank or literal null markers may represent missing values. | Standardize them to NULL without replacing missing population with zero. |
| Zero is a valid lower age limit. | Preserve age_min = 0 for the 0–4 age group. |
| `_run_id` identifies the ingestion run. | Retain it as run_id with. |
| Silver needs a processing timestamp. | Add processed_at as TIMESTAMP using the Silver processing time. |
| Only the proposed columns are required in Silver. | Exclude other columns from Silver while retaining them in Bronze. |
| Age and sex breakdowns are available. | Retain these breakdowns within Silver’s 2021–2025 scope. |
| Philippines represents the national total. | Remove it in Silver; finding the total can just be aggregated as the sum of all regions if the group agrees. |
| No duplicates were found. | Recheck region_code + year + age_group + sex uniqueness after cleaning. |
| NIR is absent from the source. | Only include regions currently present in the data, and do not fill in NIR values if they are missing. |
| Manual addition of all regional values differs from the Total/Philippines level for 2022, 2023 and 2024. | Use the aggregated amounts of all regions. |

Recheck data after filtering Silver to 2021–2025.



