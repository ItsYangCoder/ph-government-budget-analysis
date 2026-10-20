# Service Access | Bronze Data Dictionary

Assigned to: **Joy**  
Updated: **20 October 2026 (Asia/Manila)**  
Assumed table: `pondolens.dev_bronze.service_access` — confirm before running SQL.

## Purpose and grain

Service access context for PondoLens regional needs analysis. One observation is identified by country, source area, year, indicator, breakdown type/value, source and unit. The supplied 400-row export has nine indicator labels, five source labels and years 2021–2025. Physical column types must be confirmed using DESCRIBE TABLE; the Markdown export supplies text representations only.

## Column definitions

| Column | Meaning | Treatment |
|---|---|---|
| `country` | Country label; Philippines in this export. | Required; validate country before excluding it from Silver. |
| `region` | Source area: 17 regional labels or National. | Year-aware crosswalk; National is not a region; no NIR inference. |
| `year` | Observation reference year, 2021–2025 in Bronze. | Validate whole year; project scope 2022 and 2024. |
| `indicator` | Source indicator label; nine distinct labels. | Select three exact APIS labels; distinguish similar JMP definitions. |
| `breakdown_type` | Total or Residence. | Selected APIS uses Total. |
| `breakdown_value` | Denominator/subgroup: All families, Consenting families, All people, Rural, Urban, etc. | Selected handwashing is Consenting families; preserve semantics. |
| `value` | Reported or prepared percentage value on 0–100 scale. | 218 missing overall; none missing in selected APIS scope. Do not multiply by 100 or fill NULL with zero. |
| `unit` | Population base and percentage unit. | APIS: % of families or % of consenting families; not interchangeable. |
| `source` | Recorded publisher/source-series label; five labels. | PSA APIS is selected; source is part of definition separation. |
| `source_url` | Recorded original source location. | Lineage, not proof that each value has been verified. |
| `notes` | Availability, derivation, estimate status, source table and geographic caveats. | Preserve final/preliminary, Sulu and NIR caveats and 2024 water derivation. |
| `_rescued_data` | Ingestion rescue payload. | All null in snapshot; nonblank requires review. |
| `_drive_file_id` | Source Drive identifier. | Ingestion lineage; not a business key. |
| `_source_file` | Source relative CSV path. | Retain in Bronze. |
| `_landing_file` | Landed volume file path. | Retain in Bronze. |
| `_source_modified_at` | Source file modification timestamp. | Not the observation reference date. |
| `_source_sheet` | Ingested sheet name. | All null; CSV has no sheet. |
| `_content_hash` | Source content fingerprint. | Audit/reprocessing aid; not indicator ID. |
| `_header_map` | Original-to-normalized column mapping serialized as JSON. | Retain ingestion metadata. |
| `_dataset_hash` | Recorded dataset fingerprint. | Audit metadata. |
| `_run_id` | Ingestion run identifier. | Not a unique business-row ID. |
| `_ingested_at` | Time of ingestion. | Keep distinct from observation year and Silver processed_at. |

## Selected definitions for 2022 and 2024

| Source indicator | Source | Denominator / unit | Meaning and caveat |
|---|---|---|---|
| At least basic drinking-water access | PSA APIS | All families / % of families | Source notes: 2022 basic includes safely managed; 2024 combines safely managed + basic rounded percentages. Not a water-quality test. |
| Basic sanitation access | PSA APIS | All families / % of families | Preserve this exact source category; do not substitute JMP at least basic sanitation. |
| Basic handwashing facilities | PSA APIS | Consenting families / % of consenting families | Denominator is families permitting observation, not all families. |

There are 108 selected APIS records: 102 regional and 6 National. A year/label-only filter also includes 12 JMP national observations and is insufficient. No region_code, geographic_level, estimate_status, service_access_id or processed_at is present as a business column in the supplied Bronze export; these must not be described as already existing.

## Safe analysis

Never sum rates across regions or add National to regional values. Do not present a simple regional average as the national survey estimate. Keep source-specific denominators and preliminary/final status visible. Missing means unavailable in this prepared snapshot, not zero. NIR and Sulu boundary changes require supported comparable geography, not string renaming.

## Proposed Silver contract

Confirm the team's current contract before implementation: persistent service_access_id; year INT; canonical region_code and region_name; mapped service/measure; breakdown type/value; percentage value; meaningful unit; processed_at TIMESTAMP. Preserve source lineage, status and derivation in Bronze and documentation even if omitted from Silver. Crosswalk schema and actual Bronze path remain to be confirmed.

## Related files

- [Profiling SQL](profiling.sql)
- [Findings](findings.md)
