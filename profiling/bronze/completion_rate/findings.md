# Completion Rate — Bronze Profiling Findings

Profiled: 19 October 2026 (Asia/Manila)  
Table: `pondolens.dev_bronze.completion_rate`  
Scope: source year labels 2021–2025  
Evidence: Databricks query results supplied by Rhea(ItsYangCoder); source CSV inspected separately.

## Dataset and grain

The source is titled **4.1.2 Completion rate**. It contains education completion percentages, not graduate headcounts. The precise indicator definition, denominator, and mapping of year labels to school years still require source metadata verification.

Each Bronze row represents one indicator × geolocation × education level × sex combination. Years 2000–2026 are stored as separate string columns (`c_2000`–`c_2026`). Value checks in this profile cover 2021–2025 only.

There are 171 rows: 19 locations (18 regions and Philippines) × 3 education levels × 3 sex categories. Education levels are Elementary, Junior High School, and Senior High School. Sex categories are Both Sexes, Female, and Male.

## Confirmed check results

| Check | Result |
|---|---:|
| Bronze rows | 171 |
| Duplicate indicator/location/education/sex keys | 0 |
| Rows with null or blank dimension values | 0 |
| Rows with non-null rescued data | 0 |
| Unexpected nonnumeric values, 2021–2025 | 0 |
| Numeric values outside 0–100, 2021–2025 | 0 |
| Rows missing required lineage fields checked | 0 |

| Year | Observations | Numeric | `..` | `...` | Null/blank | Minimum | Maximum |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2021 | 171 | 162 | 9 | 0 | 0 | 84.1 | 100.0 |
| 2022 | 171 | 162 | 9 | 0 | 0 | 63.8 | 100.0 |
| 2023 | 171 | 162 | 9 | 0 | 0 | 46.0 | 98.7 |
| 2024 | 171 | 171 | 0 | 0 | 0 | 64.0 | 99.0 |
| 2025 | 171 | 0 | 0 | 171 | 0 | — | — |

The 9 missing observations in each of 2021–2023 all belong to NIR: 3 education levels × 3 sex categories. NIR has numeric observations in 2024. The cause of historical missingness and regional boundary comparability have not been verified.

All 2025 observations contain `...`. The source has a 2025 column but no numeric completion rates for that year. The exact meanings of `..` and `...` remain unverified; retain their distinction.

Reshaping all five project years while preserving missing observations produces 855 observations: 657 numeric and 198 missing. These totals include national records and all sex categories.

## Lineage

- Source: `05_development_indicators/06_student_completion_rate/4.1.2 Completion rate.csv`
- Drive file ID: `1eA7adP6wrQ3Fu7ZdWg_7HsMkWqQvewqy`
- Run ID: `06348391a60e4b3bb71634792d2a6f73`
- Rows: 171
- Earliest and latest ingestion: `2026-10-18T18:59:48.628+00:00`
- Required lineage check covered nonblank Drive ID, landing path, content hash, dataset hash, run ID, and non-null ingestion timestamp. It did not validate hash correctness or source timestamp parsing.
- A null source sheet is expected for CSV input.

## Proposed Silver treatments

1. Preserve Bronze as received. Unpivot only 2021–2025 into year and completion_rate; retain rows with missing measures.
2. Cast numeric rates to DECIMAL(6,3), keeping percentages on the 0–100 scale. Convert markers to NULL in the numeric measure, preserve raw values and distinguish marker statuses without assigning unverified meanings.
3. Remove leading hierarchy dots from standardized region labels. Preserve raw labels and footnote references; verify notes `1/`, `2/`, `3/`, and `4/` before finalizing mappings.
4. Map regional labels through the shared region crosswalk. Classify Philippines as national and regional records as region. Check unmatched mappings and duplicate keys again after normalization.
5. Retain education and sex categories separately. Proposed Silver natural key: indicator × region_code × education level × sex × year.
6. Preserve source lineage and add processing metadata when implementing Silver.

These are proposed rules; no Silver transformation is claimed as implemented by this profile.

## Analytical use and limitations

- Numeric coverage is 2021–2024, with NIR gaps in 2021–2023. Show 2025 as unavailable; do not impute zero or carry forward 2024.
- Use Both Sexes for overall comparisons at a selected education level. Do not add Both Sexes, Female, and Male rates together.
- Rates must not be summed. Do not derive national rates by averaging regions without valid denominator weights; use supplied national observations.
- Match budget data at compatible year and geographic grains, with an explicit education/sex selection. Otherwise joins can repeat budget amounts across indicator breakdowns.
- Completion rates alone cannot establish that spending caused an education outcome or explain budget execution gaps.

## Assessment and open verification

Structural, uniqueness, numeric-range, and checked lineage tests passed for this snapshot. Source coverage gaps remain. Analytical readiness depends on verifying the official definition and denominator, year-to-school-year interpretation, missing-marker meanings, and regional footnotes/boundary changes.
