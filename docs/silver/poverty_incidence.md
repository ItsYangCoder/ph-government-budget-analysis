# Poverty Incidence — Silver

Documented by: **Mia Barroga**  
Updated: 22 October 2026 (Asia/Manila)  
Table: `pondolens.dev_silver.poverty_incidence`  
Model: [poverty_incidence.sql](../../dbt/models/silver/poverty_incidence.sql)

## Purpose

Stores regional poverty estimates for comparison across regions and years. Poverty incidence among families and among population are kept as separate indicators.

One row represents **one year + region_code + indicator**. The dataset covers **2021, 2023, and 2025**, with 18 regions and two indicators per year. The expected coverage is **108 rows**. National and subregional records remain in Bronze; missing years are not filled.

## Data dictionary

| Column | Type | Meaning |
|---|---|---|
| poverty_incidence_id | BIGINT | Record ID starting at 9,000,001. Existing business keys keep their IDs on rerun. |
| year | INT | Source observation year: 2021, 2023, or 2025. |
| region_code | STRING | Standard project region code, such as IVA, IVB, or NIR. This is not a PSGC code. |
| region_name | STRING | Region name from the crosswalk, stored in uppercase by this model. |
| indicator | STRING | `poverty_incidence_families` or `poverty_incidence_population`. |
| poverty_threshold_php | DECIMAL(10,2) | Source annual poverty threshold in PHP per person. |
| poverty_incidence_pct | DECIMAL(5,2) | Poverty estimate in percentage points; 12.5 means 12.5%. |
| estimate_marker | STRING | `<0.05%` when note c/ applies and the estimate is below 0.05; otherwise NULL. |
| display_value | STRING | Display label: percentage with one decimal place, or `<0.05%`. Use the numeric column for calculations. |
| coefficient_of_variation | DECIMAL(5,2) | Source CV in percent. Dash or blank markers become NULL. |
| standard_error | DECIMAL(5,2) | Standard error of the percentage estimate, in percentage points. |
| ci_lower_pct | DECIMAL(5,2) | Lower limit of the source 95% confidence interval. |
| ci_upper_pct | DECIMAL(5,2) | Upper limit of the source 95% confidence interval. |
| unit | STRING | `% of families` or `% of population`. |
| value_status | STRING | `available` or `below_0_05_pct`. |
| reliability_note | STRING | `use with caution` when numeric CV exceeds 10%; otherwise NULL. |
| sig_change_2021_2023 | BOOLEAN | Whether source notes contain 1/, the significance marker for 2021–2023. |
| sig_change_2023_2025 | BOOLEAN | Whether source notes contain 2/, the significance marker for 2023–2025. |
| revised_sulu_transfer | BOOLEAN | Whether source notes contain revision marker r1/. |
| revised_north_cotabato_transfer | BOOLEAN | Whether source notes contain revision marker r2/. |
| region_mapping_source | STRING | `shared_region_crosswalk` or `poverty_override`. |
| notes | STRING | Source footnotes retained for interpretation and review. |
| source_page | STRING | Source table/page label, such as tab1 or tab2. |
| source_row | INT | Source row reference. |
| _processed_at | TIMESTAMP | Timestamp of insertion or a detected record update. Unchanged rows retain their timestamp. |

The primary key is `poverty_incidence_id`. The business key is `(year, region_code, indicator)`. SQL checks and dbt tests validate uniqueness; the primary-key declaration alone does not enforce it.

## Transformation rules

- Read regional records from Bronze and map their region labels through `shared_region_crosswalk`, using the source year and crosswalk validity dates.
- Store standard region codes and uppercase region names. Keep families and population as separate indicators.
- Parse measures as decimals. Estimates use two decimal places; percentage values are not multiplied by 100.
- Map NIR for 2021 and 2023 through a poverty-specific override. This preserves the supplied historical records without changing the shared crosswalk.
- Convert dash CV markers to NULL. Original values remain in Bronze.
- Show `<0.05%` when source note c/ applies and the parsed estimate is below 0.05%. A displayed zero with this marker does not mean no poverty.
- Set `reliability_note` to `use with caution` when CV exceeds 10%.
- Retain source notes and row references. Significance and revision flags come from source footnotes, not tests calculated by the pipeline.

## Quality checks

The SQL validates selected regional records before loading:

- Supported years and indicators, with mapped region codes.
- Positive poverty thresholds and estimates between 0% and 100%.
- Valid numeric measures, required SE/CI values, and estimates within their confidence intervals.
- CV present for nonzero estimates; dash CV is allowed for zero estimates.
- No ambiguous best region mappings, duplicate business keys, or duplicate IDs.
- Mapping preserves the selected regional row count.

The load stops when a staged year has fewer than 80% of its existing Silver rows. This guard compares years present in the stage; it does not check a completely absent year.

[dbt tests](../../dbt/models/silver/schema.yml) check nonempty output, ID uniqueness, business-key uniqueness, and required columns. The final SQL summary reports coverage, IDs, NIR overrides, and reliability markers for review.

## Load and rerun behavior

The model uses a Delta MERGE. Existing business keys keep their IDs, changed records are updated, and new keys receive IDs after the current maximum, starting at **9,000,001**.

Rows missing from the source are removed only for years included in the current load. Unchanged records keep their processing timestamp.

Run through dbt after successful Bronze ingestion and crosswalk preparation, with **one concurrent writer**. dbt resolves the catalog and schema from the environment configuration. For failed runs, follow [pipeline recovery](../ingestion.md#pipeline-failures-and-recovery).

## Usage notes

- Select one indicator before joining poverty data to regional budgets to avoid repeating budget amounts.
- Do not sum poverty percentages or use a simple regional average as the national rate.
- Use the numeric estimate for calculations and `display_value` for labels. Keep reliability notes and source markers visible when relevant.
- Check reference periods and boundary revisions before comparing datasets. The historical NIR override does not establish boundary compatibility with historical budgets.
- The 2025 poverty reference period and release status remain subject to source publication verification; the annual threshold heading alone does not establish them.
- Spending comparisons show relationships, not proof that spending caused a poverty change.

## Related files

- [Silver transformation SQL](../../dbt/models/silver/poverty_incidence.sql)
- [Silver column definitions and dbt tests](../../dbt/models/silver/schema.yml)
- [Bronze profiling SQL](../../profiling/bronze/poverty_incidence/profiling.sql)
- [Bronze findings](../../profiling/bronze/poverty_incidence/findings.md)
- [Bronze data dictionary](../../profiling/bronze/poverty_incidence/data_dictionary.md)
- [Shared region crosswalk](../shared_region_crosswalk.md)
