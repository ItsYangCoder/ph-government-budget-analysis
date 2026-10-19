# GRDP per Capita — Bronze Data Dictionary

Assigned to: Anje  
Updated: 20 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.grdp_per_capita`  
Source label: `2018-2025 GRDP_Reg_(with NIR as of April 2026)`  
Project scope: 2021–2025; full ingested coverage: 2018–2025

## Purpose and grain

Stores economic output per person by source year, geography, and price basis. GRDP per capita is distinct from total GRDP. National observations are also present in this source table.

One business observation represents **year × geography × price basis × geographic level**. Resolve source geography through the shared crosswalk before assigning the final Silver natural key. Neither `region_id` nor the ingestion run identifier is a unique row identifier.

## Source columns

The following types are the actual Bronze types supplied by the owner. Nullability descriptions are observed behavior or validation expectations, not declared database constraints.

| Column | Bronze type | Meaning and treatment |
|---|---|---|
| `source_name` | STRING | Source workbook/report label. Observed: `2018-2025 GRDP_Reg_(with NIR as of April 2026)`. |
| `source_page` | STRING | Extracted worksheet label; observed `Capita`. |
| `region_id` | STRING | Source geographic code, such as NCR, IV-A, or NIR. Blank for Philippines and MIMAROPA; resolve using the accompanying name. |
| `region` | STRING | Source geography name; includes Philippines and regional names. |
| `year` | STRING | Source year label. Parse and validate before applying the 2021–2025 project filter. |
| `grdp_per_capita_amount` | STRING | Decimal measure text in Philippine pesos per person. Preserve original text in Bronze. |
| `price_basis` | STRING | `At Current Prices` or `At Constant 2018 Prices`. These are separate observations. |
| `unit` | STRING | Observed `Philippine pesos per person`. No thousand-peso scaling applies. |
| `geographic_level` | STRING | `region` or `country`. Proposed Silver naming: `region` or `national`. |
| `source_table` | STRING | Source table reference: Table 2.1 for current prices; Table 2.2 for constant prices. |
| `source_file` | STRING | Source-supplied file/report identifier. Distinct from pipeline `_source_file`. |

## Ingestion columns

| Column | Bronze type | Meaning |
|---|---|---|
| `_rescued_data` | STRING | Payload retained when ingestion encounters unexpected fields or parsing issues. Nonblank content requires review. |
| `_drive_file_id` | STRING | Google Drive source file identifier. |
| `_source_file` | STRING | Relative source path recorded by the ingestion pipeline. |
| `_landing_file` | STRING | Landed file path under the Unity Catalog volume. |
| `_source_modified_at` | STRING | Source modification timestamp recorded as text. |
| `_source_sheet` | STRING | Ingestion worksheet selection; NULL is valid for a CSV input. |
| `_content_hash` | STRING | Fingerprint used by the ingestion pipeline to track source content. |
| `_header_map` | STRING | Serialized mapping between normalized Bronze headers and source headers. |
| `_dataset_hash` | STRING | Dataset fingerprint recorded by the ingestion pipeline. |
| `_run_id` | STRING | Ingestion execution identifier; shared by multiple rows. |
| `_ingested_at` | TIMESTAMP | Ingestion timestamp. |

## Observed categories and coverage

| Property | Observed value |
|---|---|
| Full Bronze observations | 296 |
| Full source years | 2018–2025 |
| Project-scope observations | 185 |
| Regions in project scope | 18 |
| National observations in project scope | 5, current prices only |
| Regional current-price observations | 90 |
| Regional constant-price observations | 90 |
| Blank source codes in scope | Philippines: 5; MIMAROPA: 10 |
| Amounts with fractional values in scope | 185 |

## Proposed Silver contract

- Natural key: `year + region_code + price_basis + geographic_level`.
- Obtain canonical codes and names from `shared_region_crosswalk`; do not replace its shared validity periods implicitly.
- Map source IV-A to project IVA, MIMAROPA to IVB, and Philippines to PHL using verified lookup candidates.
- Proposed amount type: `DECIMAL(20,6)` to retain fractional pesos with explicit six-decimal rounding. This is a proposal, not the current Silver implementation.
- Proposed price-basis encoding: 2018 for constant prices; the observation year for current prices. This encoding is unambiguous within 2021–2025; extending Silver to 2018 requires a separate basis category to distinguish both series.
- Keep current and constant observations separate; do not sum or average them together.
- Resolve historical NIR boundary applicability before treating mapped observations as comparable to budget geography.

## Related files

- [Profiling SQL](profiling.sql)
- [Findings](findings.md)
