# Hospital Data Dictionary

**Bronze table:** `pondolens.dev_bronze.hospital`  
**Observed grain:** one record per year and region  
**Observed rows:** 68 (2021–2024; 17 regions)  
**Observed category:** Government regulated hospitals only

The Bronze table stores the fields below as `STRING`. Convert year and hospital count to integers in Silver after validation.

| Column | Bronze type | Meaning | Expected value or rule | Observed / nullable | Silver treatment |
|---|---|---|---|---|---|
| `year` | STRING | Year of the hospital count | 2021–2024 in the current dataset | No nulls observed | Cast to INT; validate allowed years |
| `region_name` | STRING | Historical source region name | One of the 17 source regions | No nulls observed | Trim and map through the shared region crosswalk |
| `hospital_type` | STRING | Ownership/category of regulated hospitals | Government in this Bronze table | Government in all 68 rows; no nulls observed | Trim and standardize to Government |
| `regulated_hospital_count` | STRING | Number of regulated hospitals for the region and year | Whole number greater than or equal to zero | No nulls, nonnumeric values, or negative values observed | Cast to INT; reject invalid values |
| `unit` | STRING | Unit for the count | hospitals | hospitals in all 68 rows; no nulls observed | Trim and standardize to hospitals |
| `source_agency` | STRING | Agency responsible for the source data | DOH Health Facilities and Services Regulatory Bureau | Source lineage field | Preserve |
| `source_publication` | STRING | Publication containing the source table | 2025 Philippine Statistical Yearbook | Source lineage field | Preserve |
| `source_table` | STRING | Table identifier in the publication | 9.18 | Source lineage field | Preserve |
| `source_page` | STRING | Page locator in the publication | 9-28 | Source lineage field | Preserve |
| `source_url` | STRING | Link to the source publication | Valid source URL | Source lineage field | Preserve |
| `coverage_note` | STRING | Note about source coverage or extraction | Retain the source note as recorded | Source lineage field | Preserve |

## Table-specific notes

- The current table has one Government hospital record per region-year. It has no Total or Private records.
- The source uses 17 historical regions and does not list Negros Island Region separately.
- The table also contains ingestion and lineage metadata columns. Keep these fields for traceability; their exact names and types are listed in the table schema.
- Do not use this table to test `Total = Government + Private`; the other two categories are absent.
- Do not impute 2025 when no source record is available.
