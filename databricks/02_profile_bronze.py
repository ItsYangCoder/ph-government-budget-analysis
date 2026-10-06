# Databricks notebook source
# MAGIC %md
# MAGIC # PondoLens Bronze Profiling
# MAGIC
# MAGIC Read-only profiling of `pondolens.bronze`. This notebook does not modify Bronze and does not create Silver or Gold tables.
# MAGIC
# MAGIC Run the inventory and schema sections first. Inspect JSON keys before using field-specific queries. Findings shown by this notebook must be reviewed against the original source before proposing a Silver rule.

# COMMAND ----------

from pyspark.sql import functions as F, types as T
import json

CATALOG = "pondolens"
SCHEMA = "bronze"
FULL_SCHEMA = f"{CATALOG}.{SCHEMA}"

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. Table inventory and lineage
# MAGIC
# MAGIC List the current Bronze tables, schemas, row counts, source IDs, and processing revisions. Revisions are profiled separately; do not add old and revised records together.

# COMMAND ----------

tables = [r.tableName for r in spark.sql(f"SHOW TABLES IN {FULL_SCHEMA}").collect()]

inventory = []
for name in sorted(tables):
    full_name = f"{FULL_SCHEMA}.{name}"
    df = spark.table(full_name)
    required = {"record_id", "source_id", "processing_key", "source_file_sha256", "extractor_version"}
    missing = sorted(required - set(df.columns))
    inventory.append((
        full_name,
        df.count(),
        ", ".join(missing) if missing else None,
        df.schema.simpleString(),
    ))

display(spark.createDataFrame(
    inventory,
    "table string, row_count long, missing_lineage_fields string, schema string"
))

lineage = None
for name in sorted(tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    cols = ["source_id", "processing_key", "source_file_sha256", "extractor_version"]
    if all(c in df.columns for c in cols):
        part = (df.groupBy(*cols).count()
                .withColumn("bronze_table", F.lit(name)))
        lineage = part if lineage is None else lineage.unionByName(part)
if lineage is not None:
    display(lineage.orderBy("bronze_table", "source_id", "processing_key"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Record-ID checks
# MAGIC
# MAGIC Check null and duplicate record IDs by table and processing revision. These checks test record identity, not business-key uniqueness.

# COMMAND ----------

id_checks = []
for name in sorted(tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    if "record_id" not in df.columns:
        continue
    revision_cols = [c for c in ["source_id", "processing_key"] if c in df.columns]
    grouped = df.groupBy(*revision_cols) if revision_cols else df.groupBy()
    check = (grouped.agg(
        F.count("*").alias("rows"),
        F.sum(F.when(F.col("record_id").isNull(), 1).otherwise(0)).alias("null_record_ids"),
        F.countDistinct("record_id").alias("distinct_record_ids"),
    ).withColumn("bronze_table", F.lit(name))
     .withColumn("duplicate_record_ids", F.col("rows") - F.col("distinct_record_ids")))
    id_checks.append(check)

if id_checks:
    combined = id_checks[0]
    for part in id_checks[1:]:
        combined = combined.unionByName(part, allowMissingColumns=True)
    display(combined.orderBy("bronze_table"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Inspect raw JSON before profiling values
# MAGIC
# MAGIC The extraction schema stores JSON as strings. First inspect representative `raw_value_json` and `dimensions_json` records and discover dimension keys. Do not invent keys.

# COMMAND ----------

for name in sorted(tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    print(f"\n=== {name} ===")
    cols = [c for c in ["source_record_locator", "raw_value_json", "dimensions_json"] if c in df.columns]
    display(df.select(*cols).limit(5))

dimension_keys = []
for name in sorted(tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    if "dimensions_json" not in df.columns:
        continue
    keys = (df.select(F.explode(F.map_keys(
                F.from_json("dimensions_json", T.MapType(T.StringType(), T.StringType()))
            )).alias("dimension_key"))
            .where(F.col("dimension_key").isNotNull())
            .distinct())
    for row in keys.collect():
        dimension_keys.append((name, row.dimension_key))

display(spark.createDataFrame(dimension_keys, "bronze_table string, dimension_key string")
        .orderBy("bronze_table", "dimension_key"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Raw values and numeric parsing
# MAGIC
# MAGIC Profile source blanks, literal zeros, dash markers, Excel errors, formulas, nonnumeric values, and successful numeric parses separately. A null `parsed_numeric` does not automatically mean the source was blank.

# COMMAND ----------

raw_schema = T.StructType([
    T.StructField("value", T.StringType()),
    T.StructField("excel_type", T.StringType()),
    T.StructField("number_format", T.StringType()),
    T.StructField("cached_value", T.StringType()),
])

value_profiles = []
for name in sorted(tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    if not {"raw_value_json", "parsed_numeric"}.issubset(df.columns):
        continue
    p = df.withColumn("_raw", F.from_json("raw_value_json", raw_schema))
    profile = p.agg(
        F.count("*").alias("rows"),
        F.sum(F.when(F.col("_raw.value").isNull(), 1).otherwise(0)).alias("source_blanks"),
        F.sum(F.when(F.trim(F.col("_raw.value")).isin("-", "–", "—"), 1).otherwise(0)).alias("source_dashes"),
        F.sum(F.when(F.col("_raw.excel_type") == "e", 1).otherwise(0)).alias("excel_errors"),
        F.sum(F.when(F.col("_raw.excel_type") == "f", 1).otherwise(0)).alias("formula_cells"),
        F.sum(F.when(F.col("parsed_numeric") == 0, 1).otherwise(0)).alias("parsed_zeros"),
        F.sum(F.when(F.col("parsed_numeric").isNotNull(), 1).otherwise(0)).alias("numeric_parse_success"),
        F.sum(F.when(
            F.col("parsed_numeric").isNull()
            & F.col("_raw.value").isNotNull()
            & ~F.trim(F.col("_raw.value")).isin("-", "–", "—")
            & (F.col("_raw.excel_type") != "e"), 1
        ).otherwise(0)).alias("other_unparsed_values"),
    ).withColumn("bronze_table", F.lit(name))
    value_profiles.append(profile)

if value_profiles:
    combined = value_profiles[0]
    for part in value_profiles[1:]:
        combined = combined.unionByName(part)
    display(combined.orderBy("bronze_table"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Quality flags and representative evidence
# MAGIC
# MAGIC Count each preserved quality flag. Then review representative records with exact source locations. Flags may be informational, unresolved source issues, or possible extraction defects; do not treat every flag as an error.

# COMMAND ----------

flag_counts = []
flag_examples = []
for name in sorted(tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    if "quality_flags" not in df.columns:
        continue
    exploded = df.withColumn("quality_flag", F.explode_outer("quality_flags"))
    counts = (exploded.where(F.col("quality_flag").isNotNull())
              .groupBy("quality_flag").count()
              .withColumn("bronze_table", F.lit(name)))
    flag_counts.append(counts)
    example_cols = [c for c in [
        "source_id", "source_record_locator", "raw_value_json",
        "parsed_numeric", "dimensions_json", "quality_flags"
    ] if c in df.columns]
    examples = (exploded.where(F.col("quality_flag").isNotNull())
                .select("quality_flag", *example_cols)
                .dropDuplicates(["quality_flag"])
                .withColumn("bronze_table", F.lit(name)))
    flag_examples.append(examples)

if flag_counts:
    combined = flag_counts[0]
    for part in flag_counts[1:]:
        combined = combined.unionByName(part)
    display(combined.orderBy("bronze_table", F.desc("count")))

if flag_examples:
    combined = flag_examples[0]
    for part in flag_examples[1:]:
        combined = combined.unionByName(part, allowMissingColumns=True)
    display(combined.orderBy("bronze_table", "quality_flag"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. Dimension values
# MAGIC
# MAGIC After the key inventory above, profile only dimensions that actually exist. This keeps years, units, measures, statuses, price bases, geography, and row kinds visible without assuming every source has the same structure.

# COMMAND ----------

wanted = {
    "year", "unit", "measure", "reporting_status", "status",
    "price_basis", "price_basis_raw", "region_raw", "row_kind",
    "source_reporting_period", "age_group_raw", "sex_raw"
}
dimension_values = []
for name, key in sorted(set(dimension_keys)):
    if key not in wanted:
        continue
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    values = (df.select(F.get_json_object("dimensions_json", f"$.{key}").alias("value"))
              .groupBy("value").count()
              .withColumn("bronze_table", F.lit(name))
              .withColumn("dimension_key", F.lit(key)))
    dimension_values.append(values)

if dimension_values:
    combined = dimension_values[0]
    for part in dimension_values[1:]:
        combined = combined.unionByName(part)
    display(combined.orderBy("bronze_table", "dimension_key", F.desc("count")))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7. MIA — Agency summary, detail, and SUCs
# MAGIC
# MAGIC Identify financial measures, years, units, reporting periods, hierarchy, subtotals, and overlaps. Raw-cell tables do not yet have verified financial row/column mappings, so completeness and business-key checks remain pending until those mappings are documented.
# MAGIC
# MAGIC Pay special attention to conflicting 2025 SUC year headers and formula/error cells. Do not sum department totals with agency details or SUC subtotals.

# COMMAND ----------

mia_tables = [t for t in tables if t.startswith("agency_")]
print("MIA tables:", sorted(mia_tables))
for name in sorted(mia_tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    display(df.select(*[c for c in [
        "source_id", "source_sheet", "source_record_locator", "raw_value_json",
        "parsed_numeric", "dimensions_json", "quality_flags", "processing_key"
    ] if c in df.columns]).limit(50))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8. RAZZ — Sector and regional budget
# MAGIC
# MAGIC Identify sector/subsector or regional row groups, units, years, reporting statuses, controls, and hierarchy. Verify representative PDF values and continuation alignment against the originals.
# MAGIC
# MAGIC Keep 2024 regional Actual Obligations and 2025 GAA (Updated) distinct. Do not combine parent totals with child rows.

# COMMAND ----------

razz_tables = [t for t in tables if t.startswith("sector_") or t.startswith("regional_")]
print("RAZZ tables:", sorted(razz_tables))
for name in sorted(razz_tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    display(df.select(*[c for c in [
        "source_id", "source_page", "source_row", "source_record_locator",
        "parsed_numeric", "dimensions_json", "quality_flags", "processing_key"
    ] if c in df.columns]).limit(50))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 9. ANJE — Population and PSGC
# MAGIC
# MAGIC Identify population years, projection basis, age/sex groups, total rows, and regional coverage. Document NIR and Sulu uncertainties.
# MAGIC
# MAGIC PSGC 2026 is a separately dated supporting reference. Do not assume 2026 geography represents 2024–2025 historical boundaries.

# COMMAND ----------

anje_tables = [t for t in tables if t.startswith("population_") or t.startswith("psgc_")]
print("ANJE tables:", sorted(anje_tables))
for name in sorted(anje_tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    display(df.select(*[c for c in [
        "source_id", "source_sheet", "source_record_locator", "raw_value_json",
        "parsed_numeric", "dimensions_json", "quality_flags", "processing_key"
    ] if c in df.columns]).limit(50))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 10. JOY — Total and per-capita GRDP
# MAGIC
# MAGIC Identify years, measures, units, current/constant-price bases, national versus regional rows, and revision notes.
# MAGIC
# MAGIC Per-capita GRDP is already per person; do not divide it by population again. Coordinate with RAZZ and ANJE before regional comparisons so geography and time bases are compatible.

# COMMAND ----------

joy_tables = [t for t in tables if "grdp" in t]
print("JOY tables:", sorted(joy_tables))
for name in sorted(joy_tables):
    df = spark.table(f"{FULL_SCHEMA}.{name}")
    display(df.select(*[c for c in [
        "source_id", "source_sheet", "source_record_locator", "raw_value_json",
        "parsed_numeric", "dimensions_json", "quality_flags", "processing_key"
    ] if c in df.columns]).limit(50))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 11. Handoff and Silver readiness
# MAGIC
# MAGIC Record findings in `docs/bronze_profiling_handoff.md`.
# MAGIC
# MAGIC Separate:
# MAGIC - informational findings,
# MAGIC - unresolved source issues,
# MAGIC - possible extraction defects.
# MAGIC
# MAGIC A source is not ready for Silver simply because it loaded correctly. Financial completeness and business-key checks remain pending for raw-cell sources until row/column mappings are verified. No Databricks results are claimed by this notebook until the cells are actually executed.
