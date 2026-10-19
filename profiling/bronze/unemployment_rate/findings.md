# Unemployment Rate — Data Profiling Documentation

Documentation and findings separated from the SQL notebook. Findings below reflect the original uploaded notebook; they are not independently verified against the underlying data.

Data profiling
- Dataset understanding: structure, columns, grain, and metadata
- Completeness — missing values, years, and geographic coverage
- Uniqueness — exact duplicates and repeated business keys
- Validity — numeric values, unemployment rates, and estimate status
- Consistency — region names, codes, geographic levels, and units
- Accuracy and reconciliation — compare regional totals with national figures and source files
- Silver treatment — determine how to clean and standardize the dataset

## 1. Dataset understanding

- relevant columns for silver: Region, year, unit, geographic_level, indicator, value, estimate_status
- Current granularity: one row represents unemployment measure for a geographic area, year, type, and estimate status
- Granularity for silver: one row represents unemployment rate for a region for a  year. 
- For silver: Only include estimate status of final for years 2022-2024, Preliminary for 2025, and not specified for 2021.

- dataset contains both unemployment rates and counts
- measured in percent and in thousand person
- no unexpected measure or units

## 2. Completeness profiling

| Issue | Check |
|--------|------|
| Negros Island Region | 2024 to 2025 only |
| Philippines | national observation mixed with regional observations |
| NCR, CAR, Regions I–XIII | expected regional observations are present |

- 10 nulls are at the city and province level, these are not relevant to BP/AP so it's okay

## 3. Uniqueness and duplicates

- No duplicates reported at the regional candidate key: year + region + unit + estimate_status. Recheck indicator and geographic level when defining the final Silver key.

## 4. Validity checks

- all unemployment rates are valid. Accepted numeric range is 0–100 inclusive; numeric parseability and missingness are checked separately. 

## 5. Consistency and geographic standardization

| Issue | Check |
|--------|------|
|(BARMM/ARMM) vs (BARMM) | BANGSAMORO AUTONOMOUS REGION IN MUSLIM MINDANAO (BARMM/ARMM) in 2021 and BANGSAMORO AUTONOMOUS REGION IN MUSLIM MINDANAO (BARMM) 2022 nwards|
|  Region IV-A vs Region IVA | Formatting inconsistency: Region IV-A vs Region IVA  in 2024 data. IV-A in 2025 data.|

## 6. Accuracy and reconciliation

- regional unemployment in thousand person is equal to national unemployment for years 2022, 2023, 2024. 2021 and 2025 data were not checked because of different estimate_status. 

## 7. Silver treatment proposal

- Proposed estimate status to select per year (pending confirmation against source revisions):

| Estimate status | Year |
| ------ | ------|
| Final | 2022 - 2024 |
| Not specified | 2021 |
| Preliminary | 2025 | 
- BARMM/ARMM should just be BARMM
- Remove dashes from region code
- Separate region code from region name
- Bronze `year` and `value` are strings, so numeric conversion must be validated.
