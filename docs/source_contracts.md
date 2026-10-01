# Source contracts and data dictionary

This document describes the implemented nine-source conversion contract. It records how the retained datasets differ and what an engineer must preserve before combining data. For detailed source tolerances and safe SQL views, see [the long-form specification](long_form.md).

## Original inputs and generated tables

The contract expects original files directly under each numbered directory in `data/raw/`. Filenames below identify the verified input set; validation also checks folder counts, extensions, source hashes and source years where applicable.

| Folder | Original files | Generated CSV datasets | CSV count |
|---|---|---|---:|
| `01_agency_actuals` | `FY 2024 SAAODB as of December 31, 2024 (FINAL).xlsx`; `FY 2025 SAODB- FINAL FOR POSTING.xlsx` | Each year: `agency_summary`, `agency_detail_candidates`, `source_numeric_candidates` | 6 |
| `02_approved_gaa` | `GAA-2024.xlsx`; `GAA-2025.xlsx` | Each year: `approved_budget`, `approved_budget_controls` | 4 |
| `03_sector_actuals` | `F.2 By Sector, 1983-2027 (1).xlsx` | `sector_expenditure`, `source_numeric_candidates` | 2 |
| `04_regional_actuals` | `2024_B6a.pdf`; `2025_B6a.pdf` | Each year: `regional_actuals` | 2 |
| `05_population` | `Statistical Tables (2020 CBPP Subnational).xlsx` | `population_projection`, `population_growth` | 2 |
| `06_development_indicator` | `02GRDP_PerCapita_2025.xlsx` | `development_indicator`, `source_numeric_candidates` | 2 |
| **Total** | **9 originals: 7 Excel and 2 PDF** | Source-specific datasets | **18** |

Eighteen CSVs do not mean the nine inputs were duplicated. A source can contain different reporting levels, controls, measures or support cells. They are separated so a budget-line total can be checked without being summed into the budget again. CSV names start with the first 16 characters of the original source SHA-256; two years can share a dataset suffix but have different source prefixes.

The full SHA-256 in each row and report is the authoritative provenance value. The filename prefix is a convenient identifier, not a replacement for the complete source hash.

## Source-specific extraction decisions

**Agency actuals.** Melt financial measures and expense classes into rows while retaining department/fund identity, sections and reporting levels. Summary totals and detail hierarchy candidates remain separate. Candidate details are retained for review, not silently promoted to agency-level facts.

**Approved GAA.** The supplied workbook budget lines already carry detailed dimensions. Preserve department/agency/program/operating-unit/fund/object codes as text. Separate the final workbook SUM into controls. Units for the verified hashes are thousand PHP, supported by documented official amount controls.

**Sector.** Preserve all seven sections: expenditure, share, growth, GDP share, per-capita values, real levels and real growth. Keep actual, program and proposed statuses separate. A column holding a growth interval is not an annual expenditure amount.

**Regional PDFs.** Read word coordinates across both pages, validate regional captions, join split numeric fragments and assign values to the correct columns. This addresses the earlier region/Cordillera alignment problem recorded in the team's capstone notes. Retain totals and source states for reconciliation, and exclude unrelated rotated text from financial table mapping. Automated alignment checks do not eliminate the need for human page-to-row review.

**Population.** Preserve year, geography and its parents, source table, age group and sex. Projection counts and growth intervals are different datasets. Regional denominator selection must choose the appropriate total-age and both-sexes rows.

**Development indicator.** Keep per-capita GRDP at current/constant prices, growth and national indices separate. Preserve the documented Table 2.6 year-header anomaly and its interpretation; a future changed header must be reviewed rather than handled by assumed column position alone.

## Retained table grains

| Dataset | What one row represents | Key dimensions and analytical restriction |
|---|---|---|
| `approved_budget` | A budget line at the source's detailed appropriation grain | Year, department, agency, program code/level, operating unit, region, division, fund, expense and subobject; choose comparable funds before aggregation |
| `approved_budget_controls` | A source control total | Year and control row; reconciliation only |
| `agency_summary` | A financial measure/expense-class observation at a specified reporting level | Year, entity, row role, section, measure and expense class; select one compatible level |
| `agency_detail_candidates` | A numeric observation from an unresolved detailed source cell | Year, sheet, row and column; exclude until hierarchy is verified |
| `sector_expenditure` | A sector/subsector observation for one measure and year or interval | Measure, year/end year, category and parent; avoid mixing statuses and levels |
| `regional_actuals` | A regional observation/state for a department or special-purpose fund | Year, department/SPF and region; controls and group totals are not department detail |
| `population_projection` | A projected population count at a geographic/age/sex grain | Source table, year, geography/parents, age and sex |
| `population_growth` | A projected growth observation for a geography and interval | Geography and interval; not a population count |
| `development_indicator` | A regional indicator for a period, measure and price basis | Year/end year, region, measure and price basis; per-capita values are not additive |
| `source_numeric_candidates` | A retained numeric/error source cell without an approved analytical role | Source, sheet, row and column; exclude from trusted analytical views |

`record_key` is a SHA-256 digest of the dataset-specific key dimensions. The local database primary key is `(source, record_key)`. A hash identifies a key; it does not prove that the chosen business grain is analytically appropriate for every use case.

## Common schema

The current writer uses **50 ordered columns** for every long-form CSV. Fields that do not apply to a dataset remain blank. The executable source of truth is `COLUMNS` in `src/pondolens/long_form.py`.

| Field group | Columns | Meaning |
|---|---|---|
| Identity and lineage | `dataset`, `record_key`, `source`, `source_sha256`, `converter_version` | Dataset identity, hashed business key, relative source path, original version and converter version |
| Period | `year`, `period` | Observation year or source period/interval label |
| Entity hierarchy | `entity`, `parent_entity`, `department_code`, `department`, `agency_code` | Original entity names/codes and source hierarchy |
| Program and operating unit | `program_code`, `program_level`, `program`, `operating_unit`, `operating_unit_name` | GAA program and organizational context |
| Geography | `region_code`, `region`, `division_code`, `division`, `province`, `geo_level`, `geography_basis` | Original geographic labels, codes, level and boundary basis |
| Fund and expense | `fund_code`, `fund`, `expense_code`, `expense_class`, `subobject_code`, `subobject` | Funding and object-of-expenditure context |
| Population and source ordering | `source_order`, `age_group`, `sex` | Source ordering and demographic grain |
| Semantics | `section`, `measure`, `record_level`, `reporting_basis`, `status`, `price_basis` | Measure, row role, financial basis, actual/program/proposed status and price basis |
| Numeric representation | `unit`, `value`, `value_php`, `value_status`, `analytical_eligible` | Original unit/value, monetary normalization, explicit parse state and eligibility flag |
| Source location | `source_table`, `source_page`, `source_row`, `source_column`, `raw_value`, `original_formula` | Original cell/page location, raw representation and formula |

CSV is a text format; current SQLite fields preserve source representation as text. Do not infer numeric identifiers or replace blanks globally with zero. `value_php` is populated for supported monetary scales only; it does not turn population, percentages or per-capita indicators into financial facts. PDF row coordinates represent vertical positions, not invented Excel row numbers.

Source formulas and cached values are preserved during extraction. `openpyxl` reads existing caches; it does not recalculate Excel formulas. Missing required formula caches trigger review instead of fabricated values.

## Explicit value states

| State | Interpretation |
|---|---|
| `ok` | A parsed numeric value, including genuine zero |
| `source_dash` | Printed dash; retained as nonnumeric source state |
| `missing` | Blank source value; distinct from dash and zero |
| `undefined_rate` | Original rate calculation such as `#DIV/0!`; not replaced with zero |
| `source_excel_error` | Original Excel error requiring review where analytically relevant |
| `missing_formula_cache` | Formula exists but the required cached value is unavailable |
| `invalid_numeric` | Value cannot be parsed under the numeric contract |
| `invalid_domain` | Parsed value violates a source/domain rule |

The current controls determine which invalid values block a source; retained candidate cells are not trusted analytical observations. PDF dashes/blanks may contribute zero only inside the printed-total reconciliation calculation. Their stored observations remain explicit source states.

## Validation and publication contract

The current converter checks source coverage, duplicate business keys, relevant numeric/domain conditions, and source-specific arithmetic or totals. Tolerances are documented in the source unit in [long_form.md](long_form.md); do not apply a generic peso tolerance to every dataset.

All source CSVs remain available for review. Only PASS sources enter the current SQLite snapshot. Review-required sources are represented in `source_status` but do not silently keep an older partition active. Publication replaces the current source snapshot in a transaction rather than appending a second copy.

For safe selection use the existing narrow views where applicable: `agency_department_financials`, `sector_actual_financials`, `regional_department_financials`, `regional_population_totals`, and `regional_grdp_current_prices`. A `validated_<dataset>` view still needs reporting-level selection; valid numeric rows can contain totals as well as details.

## Department mapping review contract

The current review CSV contains these columns:

```text
year
actual_department
candidate_gaa_department_code
candidate_gaa_department
match_method
review_status
scope_verified
review_notes
```

The generator removes a trailing abbreviation, normalizes whitespace/case, and proposes exact normalized-name candidates within the same year. It does not use automatic fuzzy matching. Multiple candidates are flagged. For the inspected review file there are 74 entries, 67 normalized-name candidates and 7 unmatched entries; all begin as `REVIEW_REQUIRED`.

Reviewers must distinguish department identity from financial scope. A confirmed name match does not establish that approved GAA and actual available appropriations cover the same funds. Review decisions need original references and explanations, especially renamed departments, aliases, fund entries and unresolved names.

Planned Silver application requires one approved mapping per `(year, actual_department)` for the intended join, no conflicting target codes, and an explicit coverage decision. Proposed review conventions are `NAME_CONFIRMED`, `REVIEW_REQUIRED` or `NO_MATCH`, with scope `YES`, `NO` or `PENDING`. These conventions are review guidance; the current generator does not implement an approval validator or mapping application.

Separate geography mappings must include year and boundary basis. Department mapping cannot serve as the lookup for region, sector, age group or price basis. Preserve original labels alongside canonical labels and record the mapping version used by a future Silver run.
