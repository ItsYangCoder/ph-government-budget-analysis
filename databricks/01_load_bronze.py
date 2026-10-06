# Databricks notebook source
# MAGIC %md
# MAGIC # Load one verified Bronze table
# MAGIC Upload a complete committed processing-key directory to a Unity Catalog Volume.
# MAGIC Set the widgets below. Run one table, inspect it, then rerun to verify zero new rows.
# MAGIC This notebook has not yet been executed in the project workspace.

# COMMAND ----------

dbutils.widgets.text("committed_directory", "", "Uploaded /Volumes/... directory")
dbutils.widgets.text("target_table", "", "catalog.schema.table")
dbutils.widgets.text("table_id", "", "Parquet table ID without extension")

# COMMAND ----------

from load_bronze import ingest_revision

directory = dbutils.widgets.get("committed_directory")
target = dbutils.widgets.get("target_table")
table_id = dbutils.widgets.get("table_id")

if not all([directory, target, table_id]):
    raise ValueError("Fill all three widgets before loading.")

result = ingest_revision(spark, directory, target, table_id)
print(result)

# COMMAND ----------

display(spark.table(target).limit(20))
