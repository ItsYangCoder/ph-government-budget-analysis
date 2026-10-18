# Regulated Hospitals: Profiling Findings

**Bronze table:** `pondolens.dev_bronze.hospital`  
**Coverage:** 2021–2024, 17 regions  
**Rows:** 68  
**Grain:** One record per region per year  
**Measure:** Government regulated hospitals
**Evidence:** Databricks query results supplied by `Joy(JoyInBytes)` ; source CSV inspected separately.


## Results

- All 68 rows are Government hospitals; unit is `hospitals`.
- Completeness checks found no missing values in year, region, hospital type, count, or unit.
- No duplicate `year + region_name + hospital_type` keys were found.
- Validity checks found no out-of-range years, nonnumeric or negative counts, unexpected hospital types, or unexpected units.
- Bronze stores `year` and `regulated_hospital_count` as strings; cast them to integers in Silver after validation.

| Year | Regional sum of government hospitals |
|---|---:|
| 2021 | 440 |
| 2022 | 434 |
| 2023 | 445 |
| 2024 | 456 |

The regional sum decreased by 6 in 2022, then increased by 11 in each of the next two years. The 2021–2024 increase was 16 hospitals (about 3.6%). Across the 68 region-year records, counts range from 12 to 58, with an average of 26.10.

## Limitations and follow-up

The table has no Total or Private hospital records, so `Total = Government + Private` cannot be tested. The regional sums have not yet been reconciled against national totals from the source publication. The source uses 17 historical regions and does not list Negros Island Region separately.

Hospital counts do not measure beds, staffing, facility size, patient capacity, travel time, or quality of care. A comparison with DOH spending shows association only; it does not prove that spending caused hospital counts to change.

## Silver treatment

Cast year and counts to integers; trim and map region names with the shared crosswalk; standardize the type and unit; preserve source metadata; and enforce uniqueness on year, standardized region, and hospital type. Keep unavailable years missing and do not impute 2025.
