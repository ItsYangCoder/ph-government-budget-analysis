# Regional Crosswalk

## Purpose

The regional crosswalk connects region names from source datasets to one standard region code and name. This allows datasets with different region-name formats to be joined consistently.

## Table

**Path:** `pondolens.dev_silver.shared_region_crosswalk`

| Column | Meaning |
|---|---|
| `source_region_name` | Region name as it appears in a source dataset |
| `region_code` | Standard short code used to identify the region |
| `region_name` | Standard region name |

## Coverage

The table contains **31 source-name variants** mapped to **17 standard regions**. Variants such as `Region I - Ilocos Region` and `Region I Ilocos Region` map to the same code, `I`, and standard name, `Ilocos Region`.

Source labels are retained as written, including punctuation, so joins can match the source data. The region codes do not use PSGC values.

## Validation

The crosswalk was checked to confirm:

- 31 source names and 17 region codes
- Each source name has exactly one mapping
- All 17 region names in `pondolens.dev_bronze.hospital` have a crosswalk match
- The Hospital Silver table has matching Bronze and Silver row counts and hospital-count totals for 2021–2024

## Example join

```sql
SELECT
  h.year,
  x.region_code,
  x.region_name,
  h.hospital_type,
  TRY_CAST(h.regulated_hospital_count AS INT) AS regulated_hospital_count
FROM pondolens.dev_bronze.hospital h
JOIN pondolens.dev_silver.shared_region_crosswalk x
  ON TRIM(h.region_name) = x.source_region_name;
```

Use the shared crosswalk as a lookup when preparing regional data for Silver. Do not create a separate region-name mapping for each dataset unless a source value is missing from the shared table.
