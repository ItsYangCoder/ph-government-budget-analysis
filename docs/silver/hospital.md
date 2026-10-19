# Hospital Silver

## Overview

The Hospital Silver table contains cleaned and standardized regional counts of regulated government hospitals.

**Source:** `pondolens.dev_bronze.hospital`  
**Silver table:** `pondolens.dev_silver.hospital`  
**Grain:** One row per year, region, and hospital type  
**Coverage:** 2021–2024; 17 regions per year

## Columns

| Column | Description |
|---|---|
| `hospital_id` | Silver record identifier; starts at 7000001 |
| `year` | Reporting year as an integer |
| `region_code` | Standard short region code from the shared crosswalk |
| `region_name` | Standard region name from the shared crosswalk |
| `hospital_type` | Hospital classification; currently `Government` |
| `regulated_hospital_count` | Number of regulated hospitals, stored as an integer |
| `unit` | Measure unit; `hospitals` |
| `source_agency` | Publishing or reporting agency from Bronze |
| `source_publication` | Source publication from Bronze |
| `source_table` | Source table or section from Bronze |
| `source_page` | Source page reference from Bronze |
| `source_url` | Source URL from Bronze |
| `coverage_note` | Source coverage notes from Bronze |
| `processed_at` | Timestamp when the Silver query ran |

## Silver transformations

- Cast `year` to integer and `regulated_hospital_count` to integer.
- Trim text fields.
- Map `region_name` from Bronze to the shared crosswalk’s `region_code` and standard `region_name`.
- Retain source provenance fields that support traceability.
- Exclude rows with invalid year or hospital count values.

## Validation results

- 68 total records and 68 unique IDs
- 17 regions for each year from 2021 through 2024
- No null IDs, region codes, or hospital counts
- No duplicate records at the year × region × hospital type grain
- Bronze and Silver row counts and hospital-count totals match for every year

| Year | Rows | Regulated government hospitals |
|---:|---:|---:|
| 2021 | 17 | 440 |
| 2022 | 17 | 434 |
| 2023 | 17 | 445 |
| 2024 | 17 | 456 |

## Interpretation note

This dataset counts regulated government hospitals by region and year. It does not represent hospital beds, total healthcare facilities, or healthcare access by itself.
