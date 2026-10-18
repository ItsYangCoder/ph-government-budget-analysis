# Completion Rate — Bronze Data Dictionary

Table: `pondolens.dev_bronze.completion_rate`  
Verified against: supplied Databricks DESCRIBE output and profiling results, 19 October 2026.  
Grain: one indicator × geolocation × education level × sex combination, with year values stored in separate columns.

## Source columns

| Column | Bronze type | Description | Observed example / rule |
|---|---|---|---|
| indicator | STRING | Source indicator label including footnote reference. | `4.1.2 Completion rate 1/`; no null/blank values in profiled rows. |
| geolocation | STRING | Source national or regional label. Hierarchy dots and footnote references are retained. | `PHILIPPINES`, `..Region IV-A 2/`, `..Negros Island Region (NIR)`; 19 distinct labels. |
| level_of_education | STRING | Education level for the reported completion percentage. | `Elementary`, `Secondary (Junior High School)`, `Secondary (Senior High School)  4/`. |
| sex | STRING | Source sex breakdown. Both Sexes is an aggregate category. | `Both Sexes`, `Female`, `Male`. |
| c_2000–c_2026 | STRING, each column | One column per source year label, inclusive. Values are completion percentages or source markers. | Numeric text such as `95.7`; markers `..` and `...`. Source year-to-school-year mapping is pending verification. |

The year-column notation denotes 27 separate columns. The `c_` prefix makes numeric source headers valid ingestion column names. There is no year column in Bronze.

## Project-year observations

| Column | Numeric observations | Marker observations | Proposed Silver value |
|---|---:|---|---|
| c_2021 | 162 | 9 × `..`, all NIR | Numeric percentage or NULL |
| c_2022 | 162 | 9 × `..`, all NIR | Numeric percentage or NULL |
| c_2023 | 162 | 9 × `..`, all NIR | Numeric percentage or NULL |
| c_2024 | 171 | None | Numeric percentage |
| c_2025 | 0 | 171 × `...` | NULL, preserving the marker |

All numeric values checked for 2021–2025 fall within 0–100. No unexpected nonnumeric values or null/blank year values were found in that scope. Earlier years and 2026 were not included in these value checks.

## Ingestion and lineage columns

| Column | Bronze type | Description / interpretation |
|---|---|---|
| _rescued_data | STRING | Ingestion rescue payload for records that could not be parsed normally; 0 non-null rows observed. |
| _drive_file_id | STRING | Google Drive source file identifier. |
| _source_file | STRING | Source path relative to the configured Drive folder. |
| _landing_file | STRING | Saved source-file path in the managed landing volume. |
| _source_modified_at | STRING | Source modification timestamp supplied by Drive; stored as text. |
| _source_sheet | STRING | Source sheet/tab where applicable; NULL is expected for this CSV. |
| _content_hash | STRING | Ingestion hash of source-file content. |
| _header_map | STRING | JSON mapping from normalized column names to original source headers. |
| _dataset_hash | STRING | Dataset fingerprint used by ingestion to detect unchanged input. |
| _run_id | STRING | Ingestion execution identifier. |
| _ingested_at | TIMESTAMP | Timestamp at which the record was ingested. |

Required lineage fields checked were _drive_file_id, _landing_file, _content_hash, _dataset_hash, _run_id, and _ingested_at; 0 incomplete rows were found. Field presence does not prove timestamp or hash validity.

## Keys, measures, and interpretation

- Bronze candidate key: `(indicator, geolocation, level_of_education, sex)`; 0 duplicates observed. This is a checked key, not a declared database constraint.
- After unpivot, year becomes part of the key. Recheck uniqueness after label normalization and region mapping.
- Measure unit: percent, retained on a 0–100 scale. A value of 95.7 represents 95.7%, not 0.957 and not 95.7 graduates.
- Proposed Silver measure type: DECIMAL(6,3); proposed year type: INT. Other proposed fields include region_code, geographic_level, raw_value, and value_status. These fields are not present in the verified Bronze schema.
- Preserve distinct source markers; their official meanings are pending verification. Never replace them with zero.
- Do not sum percentages, combine aggregate and sex-specific rates, or mix national and regional records in regional totals.
- The exact completion-rate denominator, school-year interpretation, and footnote definitions must be verified before analytical use.

See `findings.md` for check results, source lineage, and proposed treatments.
