-- Dataset: agency_actuals
-- Table: pondolens.dev_bronze.agency_actuals
-- Owner: Mia Barroga
-- Scope: reference_only
-- Execute the complete file in one Databricks SQL session.
-- Persistent tables are read-only; session TEMP VIEWs are allowed.
-- Evidence and unresolved checks: findings.md. Column definitions: data_dictionary.md.

-- Agency Actuals Bronze profiling
-- Assigned to / documented by: Mia Barroga
-- Scope: 2021–2025. Run the full file in one Databricks SQL session.
-- Read-only checks; temporary views do not modify Bronze.

DESCRIBE TABLE pondolens.dev_bronze.agency_actuals;

CREATE OR REPLACE TEMP VIEW agency_actuals_profile AS
WITH labels AS (
 SELECT *,
 COALESCE(NULLIF(TRIM(fiscal_year), ''), NULLIF(TRIM(year), '')) AS year_label,
 COALESCE(NULLIF(TRIM(column_group), ''), NULLIF(TRIM(budget_stage), '')) AS stage_label,
 COALESCE(NULLIF(TRIM(source_sheet), ''), NULLIF(TRIM(source_page), '')) AS page_label,
 COALESCE(NULLIF(TRIM(row_no), ''), NULLIF(TRIM(source_row), '')) AS row_reference,
 COALESCE(NULLIF(TRIM(row_group), ''), NULLIF(TRIM(category), '')) AS category_label,
 UPPER(COALESCE(NULLIF(TRIM(class), ''), NULLIF(TRIM(expense_class), ''))) AS class_label,
 CASE WHEN NULLIF(TRIM(percent_amount), '') IS NOT NULL THEN 'percent'
 ELSE LOWER(COALESCE(NULLIF(TRIM(unit), ''), NULLIF(TRIM(unit_amount), ''))) END AS measure_unit
 FROM pondolens.dev_bronze.agency_actuals
), measures AS (
 SELECT *, CASE WHEN measure_unit = 'percent'
 THEN COALESCE(NULLIF(TRIM(percent_amount), ''), NULLIF(TRIM(value), ''))
 ELSE COALESCE(NULLIF(TRIM(amount), ''), NULLIF(TRIM(value), '')) END AS raw_measure
 FROM labels
), normalized AS (
 SELECT *, CASE
 WHEN raw_measure IS NULL THEN 'missing'
 WHEN raw_measure IN ('-', '–', '—') THEN 'dash_marker'
 WHEN raw_measure = '#DIV/0!' THEN 'source_formula_error'
 ELSE 'provided' END AS measure_status,
 CASE WHEN raw_measure RLIKE '^[(].*[)]$'
 THEN CONCAT('-', REPLACE(SUBSTRING(raw_measure, 2, LENGTH(raw_measure) - 2), ',', ''))
 ELSE REPLACE(raw_measure, ',', '') END AS numeric_text
 FROM measures
)
SELECT *,
 CASE WHEN measure_unit = 'percent'
 AND numeric_text RLIKE '^[+-]?[0-9]+([.][0-9]+)?[ ]*%?$'
 THEN TRY_CAST(TRIM(REPLACE(numeric_text, '%', '')) AS DECIMAL(30,10))
 WHEN measure_unit = 'thousand pesos'
 THEN TRY_CAST(numeric_text AS DECIMAL(30,10)) END AS numeric_measure
FROM normalized;

-- 1. Source inventory and missing fields.
SELECT _source_file, year_label, COUNT(*) AS total_rows,
 COUNT_IF(NULLIF(TRIM(particulars), '') IS NULL) AS missing_particulars,
 COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows
FROM agency_actuals_profile GROUP BY _source_file, year_label
ORDER BY year_label;

-- 2. Source labels: inspect layout and hierarchy before choosing a Silver grain.
SELECT year_label, row_type, category_label, stage_label, class_label,
 measure_unit, percent_type, COUNT(*) AS row_count
FROM agency_actuals_profile
GROUP BY year_label, row_type, category_label, stage_label, class_label, measure_unit, percent_type
ORDER BY year_label, row_type, stage_label, class_label;

-- 3. Numeric checks. Negative monetary amounts are observations, not automatic failures.
SELECT year_label, measure_unit, COUNT(*) AS total_rows,
 COUNT_IF(measure_status = 'missing') AS missing_values,
 COUNT_IF(measure_status = 'dash_marker') AS dash_markers,
 COUNT_IF(measure_status = 'source_formula_error') AS formula_errors,
 COUNT_IF(measure_status = 'provided' AND numeric_measure IS NULL) AS invalid_numeric_values,
 COUNT_IF(numeric_measure < 0) AS negative_values,
 COUNT_IF(numeric_measure <> FLOOR(numeric_measure)) AS fractional_values,
 COUNT_IF(measure_unit = 'percent' AND numeric_measure > 100) AS percentages_above_100,
 MIN(numeric_measure) AS minimum_value, MAX(numeric_measure) AS maximum_value
FROM agency_actuals_profile GROUP BY year_label, measure_unit
ORDER BY year_label, measure_unit;

-- 4. Markers and formula errors: retain their source context.
SELECT year_label, particulars, row_type, category_label, stage_label,
 class_label, percent_type, raw_measure, page_label, row_reference, source_cell
FROM agency_actuals_profile
WHERE measure_status IN ('missing', 'source_formula_error')
 OR (measure_status = 'provided' AND numeric_measure IS NULL)
ORDER BY year_label, row_reference, stage_label;

-- 5. Negative monetary values outside Adjustments.
SELECT year_label, particulars, row_type, category_label, stage_label,
 class_label, raw_measure, numeric_measure, value_as_shown, footnote,
 page_label, row_reference, source_cell
FROM agency_actuals_profile
WHERE measure_unit = 'thousand pesos' AND numeric_measure < 0
 AND UPPER(TRIM(stage_label)) <> 'ADJUSTMENTS'
ORDER BY year_label, particulars, stage_label;

-- 6. Blank labels: distinguish source totals from missing agency names.
SELECT year_label, row_type, category_label, page_label, row_reference, COUNT(*) AS rows
FROM agency_actuals_profile WHERE NULLIF(TRIM(particulars), '') IS NULL
GROUP BY year_label, row_type, category_label, page_label, row_reference;

-- 7. Earlier source-coordinate duplicate check.
SELECT _source_file, source_sheet, source_cell, COUNT(*) AS rows
FROM agency_actuals_profile
WHERE NULLIF(TRIM(source_cell), '') IS NOT NULL
GROUP BY _source_file, source_sheet, source_cell HAVING COUNT(*) > 1;

-- 8. Later source-coordinate duplicate check.
SELECT _source_file, source_page, source_row, row_type, category,
 budget_stage, NULLIF(TRIM(expense_class), '') AS expense_class_key,
 NULLIF(TRIM(percent_type), '') AS percent_type_key, measure_unit, COUNT(*) AS rows
FROM agency_actuals_profile WHERE year_label IN ('2024', '2025')
GROUP BY _source_file, source_page, source_row, row_type, category, budget_stage,
 NULLIF(TRIM(expense_class), ''), NULLIF(TRIM(percent_type), ''), measure_unit
HAVING COUNT(*) > 1;

-- 9. Expense-class reconciliation. Partial sums are not comparable totals.
CREATE OR REPLACE TEMP VIEW agency_actuals_class_checks AS
WITH grouped AS (
 SELECT _source_file, year_label, page_label, row_reference, particulars, row_type, stage_label,
 COUNT_IF(class_label = 'TOTAL') AS total_rows,
 COUNT_IF(class_label IN ('PS','MOOE','FINEX','CO')) AS component_rows,
 COUNT(DISTINCT CASE WHEN class_label IN ('PS','MOOE','FINEX','CO') THEN class_label END) AS distinct_components,
 COUNT_IF(numeric_measure IS NULL) AS unresolved_measures,
 COUNT_IF(measure_status = 'dash_marker') AS dash_markers,
 MAX(CASE WHEN class_label = 'TOTAL' THEN numeric_measure END) AS reported_total,
 SUM(CASE WHEN class_label IN ('PS','MOOE','FINEX','CO') THEN numeric_measure END) AS component_sum
 FROM agency_actuals_profile WHERE measure_unit = 'thousand pesos'
 AND class_label IN ('PS','MOOE','FINEX','CO','TOTAL')
 GROUP BY _source_file, year_label, page_label, row_reference, particulars, row_type, stage_label
)
SELECT *, CASE WHEN total_rows <> 1 OR component_rows <> 4 OR distinct_components <> 4
 THEN 'REVIEW_STRUCTURE'
 WHEN unresolved_measures > 0 THEN 'REVIEW_MARKERS_OR_MISSING'
 WHEN reported_total = component_sum THEN 'MATCH' ELSE 'DIFFERENCE' END AS check_status
FROM grouped;

SELECT year_label, check_status, COUNT(*) AS checked_groups,
 MAX(CASE WHEN check_status IN ('MATCH','DIFFERENCE')
 THEN ABS(reported_total - component_sum) END) AS maximum_absolute_difference
FROM agency_actuals_class_checks GROUP BY year_label, check_status ORDER BY year_label, check_status;

SELECT year_label, COUNT(*) AS review_groups,
 COUNT_IF(unresolved_measures = dash_markers) AS dash_only_groups
FROM agency_actuals_class_checks WHERE check_status = 'REVIEW_MARKERS_OR_MISSING'
GROUP BY year_label;

-- 10. Stage equations. Extracted logical row references bridge earlier sheets.
-- Inspect any source-coordinate ambiguity before accepting cross-sheet matches.
CREATE OR REPLACE TEMP VIEW agency_actuals_equation_checks AS
WITH stages AS (
 SELECT _source_file, year_label, row_reference, particulars, row_type, category_label,
 CASE WHEN class_label IN ('PS','MOOE','FINEX','CO','TOTAL') THEN class_label ELSE 'TOTAL' END AS expense_class_label,
 CASE UPPER(TRIM(stage_label))
 WHEN 'APPROPRIATIONS' THEN 'appropriations'
 WHEN 'ADJUSTMENTS' THEN 'adjustments'
 WHEN 'TOTAL AVAILABLE APPROPRIATIONS' THEN 'available'
 WHEN 'ALLOTMENTS' THEN 'allotments'
 WHEN 'OBLIGATIONS INCURRED' THEN 'obligations'
 WHEN 'UNOBLIGATED ALLOTMENTS' THEN 'unobligated'
 WHEN 'UNRELEASED APPRO.' THEN 'unreleased'
 WHEN 'UNRELEASED APPROPRIATIONS' THEN 'unreleased' END AS stage_key,
 numeric_measure
 FROM agency_actuals_profile WHERE measure_unit = 'thousand pesos'
), definitions AS (
 SELECT * FROM VALUES
 ('appropriations_plus_adjustments','appropriations','adjustments','available',1),
 ('allotments_minus_obligations','allotments','obligations','unobligated',-1),
 ('available_minus_allotments','available','allotments','unreleased',-1)
 AS d(equation, first_stage, second_stage, output_stage, second_sign)
), grouped AS (
 SELECT s._source_file, s.year_label, s.row_reference, s.particulars, s.row_type,
 s.category_label, s.expense_class_label, d.equation,
 COUNT_IF(s.stage_key = d.first_stage) AS input_one_rows,
 COUNT_IF(s.stage_key = d.second_stage) AS input_two_rows,
 COUNT_IF(s.stage_key = d.output_stage) AS output_rows,
 MAX(CASE WHEN s.stage_key = d.first_stage THEN s.numeric_measure END)
 + d.second_sign * MAX(CASE WHEN s.stage_key = d.second_stage THEN s.numeric_measure END) AS computed_amount,
 MAX(CASE WHEN s.stage_key = d.output_stage THEN s.numeric_measure END) AS reported_amount
 FROM stages s CROSS JOIN definitions d
 WHERE s.stage_key IN (d.first_stage,d.second_stage,d.output_stage)
 GROUP BY s._source_file,s.year_label,s.row_reference,s.particulars,s.row_type,
 s.category_label,s.expense_class_label,d.equation,d.second_sign
 HAVING COUNT_IF(s.stage_key = d.output_stage) > 0
)
SELECT *, computed_amount - reported_amount AS difference,
 CASE WHEN input_one_rows <> 1 OR input_two_rows <> 1 OR output_rows <> 1 THEN 'REVIEW_STRUCTURE'
 WHEN computed_amount IS NULL OR reported_amount IS NULL THEN 'REVIEW_MARKERS_OR_MISSING'
 WHEN computed_amount = reported_amount THEN 'MATCH' ELSE 'DIFFERENCE' END AS check_status
FROM grouped;

SELECT year_label,equation,check_status,COUNT(*) AS checked_groups,
 MAX(CASE WHEN check_status IN ('MATCH','DIFFERENCE') THEN ABS(difference) END) AS maximum_absolute_difference
FROM agency_actuals_equation_checks GROUP BY year_label,equation,check_status
ORDER BY year_label,equation,check_status;

SELECT * FROM agency_actuals_equation_checks
WHERE check_status IN ('DIFFERENCE','REVIEW_STRUCTURE')
ORDER BY ABS(difference) DESC NULLS LAST,year_label LIMIT 100;

-- 11. Trace the confirmed source inconsistency and precision difference.
SELECT year,source_page,source_row,particulars,budget_stage,expense_class,amount,unit_amount,_source_file
FROM pondolens.dev_bronze.agency_actuals
WHERE TRIM(year) = '2024' AND UPPER(TRIM(particulars)) = 'OFFICE OF THE PRESIDENT'
 AND UPPER(TRIM(budget_stage)) IN ('APPROPRIATIONS','ADJUSTMENTS','TOTAL AVAILABLE APPROPRIATIONS')
ORDER BY budget_stage,expense_class;

-- 12. Ingestion lineage completeness; missing source_cell is checked separately.
SELECT _source_file,_run_id,COUNT(*) AS row_count,
 COUNT_IF(NULLIF(TRIM(_drive_file_id),'') IS NULL OR NULLIF(TRIM(_source_file),'') IS NULL
 OR NULLIF(TRIM(_landing_file),'') IS NULL OR NULLIF(TRIM(_source_modified_at),'') IS NULL
 OR NULLIF(TRIM(_content_hash),'') IS NULL OR NULLIF(TRIM(_header_map),'') IS NULL
 OR NULLIF(TRIM(_dataset_hash),'') IS NULL OR NULLIF(TRIM(_run_id),'') IS NULL
 OR _ingested_at IS NULL) AS incomplete_lineage_rows,
 MIN(_ingested_at) AS earliest_ingestion,MAX(_ingested_at) AS latest_ingestion
FROM agency_actuals_profile GROUP BY _source_file,_run_id ORDER BY _source_file;
