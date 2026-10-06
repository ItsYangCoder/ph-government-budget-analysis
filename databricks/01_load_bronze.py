# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "6"
# ///
# MAGIC %md
# MAGIC ## 1. Setup
# MAGIC
# MAGIC Prepare the libraries, file paths, and SHA-256 function used by the notebook.
# MAGIC - Source: uploaded extraction files in the Volume.
# MAGIC - Destination: `pondolens.bronze`.
# MAGIC This step does not load or change data.

# COMMAND ----------

from pathlib import Path
import hashlib
import json
import re

from delta.tables import DeltaTable
from pyspark.sql import functions as F

ROOT = Path(
    "/Volumes/pondolens/bronze/bronze_ingestion_files/committed"
)
TARGET_SCHEMA = "pondolens.bronze"

def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

print("Setup ready")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. Verify Uploaded Files
# MAGIC
# MAGIC Check that the uploaded extraction packages are complete and unchanged.
# MAGIC Verify file hashes, required files, recorded row counts, and extraction validation results.
# MAGIC Expected for this batch: **18 packages containing 21 Parquet tables**.
# MAGIC Loading stops if a required check fails. Extra `.DS_Store` files are ignored.

# COMMAND ----------

files_verified = False

if not ROOT.is_dir():
    raise FileNotFoundError(f"Folder not found: {ROOT}")

manifests = sorted(ROOT.glob("*/*/manifest.json"))

if len(manifests) != 18:
    raise ValueError(f"Expected 18 packages; found {len(manifests)}.")

load_plan = []
referenced_files = set()
seen_keys = set()

for manifest_path in manifests:
    directory = manifest_path.parent
    manifest = json.loads(manifest_path.read_text())

    source_id = manifest["source_id"]
    key = manifest["processing_key"]

    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", source_id):
        raise ValueError(f"Invalid source ID: {source_id}")

    if directory.name != key or directory.parent.name != source_id:
        raise ValueError(f"Folder structure mismatch: {directory}")

    if key in seen_keys:
        raise ValueError(f"Repeated processing key: {key}")
    seen_keys.add(key)

    entries = manifest["files"]
    names = [entry["path"] for entry in entries]

    if len(names) != len(set(names)):
        raise ValueError(f"Duplicate manifest entries: {source_id}")

    required = {"original.bin", "metadata.json", "validation.json"}
    if not required.issubset(names):
        raise ValueError(f"Missing required entries: {source_id}")

    referenced_files.add(manifest_path)
    parquet_entries = []

    for entry in entries:
        name = entry["path"]

        if Path(name).name != name:
            raise ValueError(f"Unsafe filename: {name}")

        path = directory / name

        if not path.is_file():
            raise FileNotFoundError(str(path))

        if sha256_file(path) != entry["sha256"]:
            raise ValueError(f"Checksum mismatch: {path}")

        referenced_files.add(path)

        if entry["kind"] == "parquet":
            parquet_entries.append(entry)

    if sha256_file(directory / "original.bin") != manifest["file_sha256"]:
        raise ValueError(f"Original digest mismatch: {source_id}")

    checks = json.loads((directory / "validation.json").read_text())

    if any(check.get("passed") is False for check in checks):
        raise ValueError(f"Failed extraction validation: {source_id}")

    if not parquet_entries:
        raise ValueError(f"No Parquet tables: {source_id}")

    if sum(entry["row_count"] for entry in parquet_entries) != manifest["row_count"]:
        raise ValueError(f"Manifest count mismatch: {source_id}")

    for entry in parquet_entries:
        table_id = Path(entry["path"]).stem

        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", table_id):
            raise ValueError(f"Invalid table ID: {table_id}")

        load_plan.append({
            "path": str(directory / entry["path"]),
            "target": f"{TARGET_SCHEMA}.{source_id}_{table_id}",
            "processing_key": key,
            "source_id": source_id,
            "source_sha256": manifest["file_sha256"],
            "expected_rows": entry["row_count"],
        })

    print(f"PASS: {source_id}")

if len(load_plan) != 21:
    raise ValueError(f"Expected 21 tables; found {len(load_plan)}.")

extras = sorted(
    str(path.relative_to(ROOT))
    for path in ROOT.rglob("*")
    if path.is_file() and path not in referenced_files
)

files_verified = True

print(f"\nVerified: {len(manifests)} packages, {len(load_plan)} tables")
print("Additional files ignored:", extras)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. Load Bronze Tables
# MAGIC
# MAGIC Load the verified Parquet records into Delta tables under `pondolens.bronze`.
# MAGIC Preserve extracted values, source information, and quality flags.
# MAGIC Use deterministic record IDs to insert only records that are not already loaded. Rerunning the same data should produce **zero new records**.
# MAGIC No Silver cleaning or analytical joins happen here.

# COMMAND ----------

if not files_verified:
    raise RuntimeError("Run Cell 2 successfully before loading.")

results = []

for item in load_plan:
    df = spark.read.parquet(item["path"])
    expected = item["expected_rows"]
    target = item["target"]

    if df.count() != expected:
        raise ValueError(f"Source row-count mismatch: {target}")

    invalid_lineage = (
        F.col("processing_key").isNull()
        | (F.col("processing_key") != item["processing_key"])
        | F.col("source_id").isNull()
        | (F.col("source_id") != item["source_id"])
        | F.col("source_file_sha256").isNull()
        | (F.col("source_file_sha256") != item["source_sha256"])
    )

    if df.filter(invalid_lineage).limit(1).count():
        raise ValueError(f"Source lineage mismatch: {target}")

    if df.filter(F.col("record_id").isNull()).limit(1).count():
        raise ValueError(f"Missing record IDs: {target}")

    if df.select("record_id").distinct().count() != expected:
        raise ValueError(f"Duplicate source record IDs: {target}")

    if not spark.catalog.tableExists(target):
        (
            df.limit(0)
            .write
            .format("delta")
            .mode("append")
            .saveAsTable(target)
        )

    existing = spark.table(target)

    # Check column names/types; Spark may change nullability in storage.
    source_types = [(field.name, field.dataType) for field in df.schema]
    target_types = [(field.name, field.dataType) for field in existing.schema]

    if source_types != target_types:
        raise ValueError(f"Target schema needs review: {target}")

    candidate_new = df.join(
        existing.select("record_id"),
        "record_id",
        "left_anti",
    ).count()

    # Existing IDs must have identical content.
    existing_matches = existing.join(
        df.select("record_id"),
        "record_id",
        "inner",
    )

    if existing_matches.select("record_id").distinct().count() != existing_matches.count():
        raise ValueError(f"Duplicate existing record IDs: {target}")

    columns = df.columns
    if existing_matches.select(*columns).exceptAll(df.select(*columns)).limit(1).count():
        raise ValueError(f"Existing record content differs: {target}")

    (
        DeltaTable.forName(spark, target)
        .alias("target")
        .merge(
            df.alias("source"),
            "target.record_id = source.record_id",
        )
        .whenNotMatchedInsertAll()
        .execute()
    )

    results.append({
        "table": target,
        "source_rows": expected,
        "candidate_new_rows": candidate_new,
    })

    print(
        f"{target}: rows={expected:,}, "
        f"candidate_new={candidate_new:,}"
    )

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Verify Loaded Data
# MAGIC
# MAGIC Compare each loaded processing revision with its source Parquet file.
# MAGIC Check row counts, unique record IDs, and all field values to confirm that loading did not lose or change records.
# MAGIC Expected for this batch: **21 tables and 798,440 records**, with all checks passing.
# MAGIC Records include raw cells and extracted measures; they are not all financial transactions.

# COMMAND ----------

summary = []

for item in load_plan:
    source = spark.read.parquet(item["path"])

    loaded = spark.table(item["target"]).filter(
        F.col("processing_key") == item["processing_key"]
    )

    actual = loaded.count()
    unique_ids = loaded.select("record_id").distinct().count()

    if actual != item["expected_rows"] or unique_ids != actual:
        raise ValueError(f"Count/uniqueness failure: {item['target']}")

    columns = source.columns

    source_only = (
        source.select(*columns)
        .exceptAll(loaded.select(*columns))
        .limit(1)
        .count()
    )
    target_only = (
        loaded.select(*columns)
        .exceptAll(source.select(*columns))
        .limit(1)
        .count()
    )

    if source_only or target_only:
        raise ValueError(f"Loaded content mismatch: {item['target']}")

    summary.append({
        "table": item["target"],
        "expected_rows": item["expected_rows"],
        "actual_rows": actual,
        "status": "PASS",
    })

display(spark.createDataFrame(summary))

print("Verified tables:", len(summary))
print("Total records/cells:", sum(row["actual_rows"] for row in summary))
print(
    "Candidate new rows this run:",
    sum(row["candidate_new_rows"] for row in results),
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Preview Bronze Data
# MAGIC
# MAGIC Display sample records from the population Bronze table.
# MAGIC Review raw values, parsed numeric values, source locations, and quality flags.
# MAGIC This preview helps us understand the extracted data. It does not modify records or replace the full verification checks.

# COMMAND ----------

display(
    spark.table("pondolens.bronze.population_projection_population")
    .select(
        "source_sheet",
        "source_record_locator",
        "raw_value_json",
        "parsed_numeric",
        "dimensions_json",
        "quality_flags",
    )
    .limit(20)
)