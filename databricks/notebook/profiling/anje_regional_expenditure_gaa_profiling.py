# Databricks notebook source
# MAGIC %md
# MAGIC # Regional GAA Profiling
# MAGIC Owner: Anje
# MAGIC Table: `pondolens.dev_bronze.regional_expenditure_gaa`
# MAGIC Baseline: 1,920 rows
# MAGIC
# MAGIC ## Goal
# MAGIC Identify data issues and propose Silver treatments. Do not modify Bronze.
# MAGIC
# MAGIC ## Checks
# MAGIC - Check counts by file/year, column types, nulls/blanks, and `_rescued_data`.
# MAGIC - Define what one row represents; check exact duplicates and repeated business keys.
# MAGIC - Verify regions, years, categories, particulars, numeric amounts, units, and price basis.
# MAGIC - Identify totals/subtotals to avoid double counting.
# MAGIC - Compare sample amounts and totals with the original source.
# MAGIC - With Joy, check whether GAA and obligations have matching scope, periods, and regions.
# MAGIC - Check regional compatibility with population and GRDP.
# MAGIC
# MAGIC ## Findings
# MAGIC | Check / Issue | Affected rows / Evidence | Proposed Silver treatment |
# MAGIC |---|---|---|
# MAGIC | Dashes in expenditure_amount column| 336 rows in 2025 table, 344 rows in 2024 table| treat as NULL since no data was inputted in the original tables|
# MAGIC | Special characters in particulars column (). The data contains both the department and the acronym of the department inside the () | 40 distinct column_value with 20 occurences each for both 2024 and 2025 tables. 39 of these values are the agency names while the other value is GAA(updated)| separate the acronym from the full agency names|
# MAGIC | when particulars = 'All', these are aggregate rows. Other particulars are department or fund detail rows rathen than automatically being subtotals | All rows| Keep all rows in Silver and add two classification columns. This preserves published totals for validation while allowing dashboards to select detail rows without double counting. financial_row_type: grand_total, category_total, detail AND geographic_row_type: geographic_total, nonregional, regional|
# MAGIC |Expenditure amount in thousand pesos|All rows| convert expenditure amount to be in thousand pesos and remove unit_amoount column|
# MAGIC |expenditure in string format|All rows|cast as BIGINT|
# MAGIC
# MAGIC ## Assumptions to Verify
# MAGIC | Interpretation / Question | Evidence | Status |
# MAGIC |---|---|---|
# MAGIC | To be completed | | Pending |
# MAGIC
# MAGIC ## Semantic Notes
# MAGIC Document the confirmed spending measure, unit conversion, and rows safe to sum.
# MAGIC Do not label GAA amounts as actual spending without source confirmation.
# MAGIC
# MAGIC ## Conclusion
# MAGIC - Required Silver changes:
# MAGIC - Ready for Q1/Q3? Why / why not:
# MAGIC - Open questions:

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT *
# MAGIC FROM pondolens.dev_bronze.regional_expenditure_gaa
# MAGIC LIMIT 10;

# COMMAND ----------

# MAGIC %sql
# MAGIC DESCRIBE TABLE pondolens.dev_bronze.regional_expenditure_gaa;

# COMMAND ----------

# MAGIC %sql
# MAGIC -- List of all regions
# MAGIC
# MAGIC SELECT
# MAGIC     DISTINCT(regions) as region_list
# MAGIC FROM pondolens.dev_bronze.regional_expenditure_gaa

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Null counts
# MAGIC SELECT
# MAGIC     COUNT(*) as total_rows,
# MAGIC     COUNT_IF(source_name IS NULL) as source_name_nulls,
# MAGIC     COUNT_IF(source_page IS NULL) as source_page_nulls,
# MAGIC     COUNT_IF(price_basis IS NULL) as price_basis_nulls,
# MAGIC     COUNT_IF(year IS NULL) as year_nulls,
# MAGIC     COUNT_IF(category IS NULL) as category_nulls,
# MAGIC     COUNT_IF(particulars IS NULL) as particulars_nulls,
# MAGIC     COUNT_IF(regions IS NULL) as regions_nulls,
# MAGIC     COUNT_IF(expenditure_amount IS NULL) as expenditure_amount_nulls,
# MAGIC     COUNT_IF(unit_amount IS NULL) as unit_amount_nulls,
# MAGIC     COUNT_IF(_rescued_data IS NULL) as _rescued_data_nulls,
# MAGIC     COUNT_IF(_ingested_at IS NULL) as ingestion_timestamp_nulls,
# MAGIC     COUNT_IF(_source_file IS NULL) as source_file_nulls
# MAGIC FROM
# MAGIC     pondolens.dev_bronze.regional_expenditure_gaa

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Duplicates
# MAGIC SELECT
# MAGIC     source_name,
# MAGIC     source_page,
# MAGIC     price_basis,
# MAGIC     year,
# MAGIC     category,
# MAGIC     particulars,
# MAGIC     regions,
# MAGIC     expenditure_amount,
# MAGIC     unit_amount,
# MAGIC     COUNT(*) AS duplicate_count
# MAGIC FROM pondolens.dev_bronze.regional_expenditure_gaa
# MAGIC GROUP BY
# MAGIC     source_name,
# MAGIC     source_page,
# MAGIC     price_basis,
# MAGIC     year,
# MAGIC     category,
# MAGIC     particulars,
# MAGIC     regions,
# MAGIC     expenditure_amount,
# MAGIC     unit_amount
# MAGIC HAVING COUNT(*) > 1;

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Check for special characters 
# MAGIC
# MAGIC WITH column_values AS (
# MAGIC     SELECT
# MAGIC         source_name AS file_name,
# MAGIC         STACK(
# MAGIC             9,
# MAGIC             'source_name', CAST(source_name AS STRING),
# MAGIC             'source_page', CAST(source_page AS STRING),
# MAGIC             'price_basis', CAST(price_basis AS STRING),
# MAGIC             'year', CAST(year AS STRING),
# MAGIC             'category', CAST(category AS STRING),
# MAGIC             'particulars', CAST(particulars AS STRING),
# MAGIC             'regions', CAST(regions AS STRING),
# MAGIC             'expenditure_amount', CAST(expenditure_amount AS STRING),
# MAGIC             'unit_amount', CAST(unit_amount AS STRING)
# MAGIC         ) AS (column_name, column_value)
# MAGIC     FROM pondolens.dev_bronze.regional_expenditure_gaa
# MAGIC )
# MAGIC SELECT
# MAGIC     file_name,
# MAGIC     column_name,
# MAGIC     column_value,
# MAGIC     COUNT(*) AS occurrences
# MAGIC FROM column_values
# MAGIC WHERE column_value RLIKE '[^a-zA-Z0-9 ]'
# MAGIC GROUP BY file_name, column_name, column_value
# MAGIC ORDER BY column_name, occurrences DESC;

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC     *
# MAGIC FROM pondolens.raw.regional_expenditure_2024
# MAGIC WHERE particulars <> 'All'
# MAGIC LIMIT 10;

# COMMAND ----------

# MAGIC %md
# MAGIC