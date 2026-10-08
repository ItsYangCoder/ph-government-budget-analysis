from pyspark.sql import functions as F

TARGET = "pondolens.dev_bronze"
ROOT = f"/Volumes/{TARGET.replace('.', '/')}/government_budget"

# Table: (source folder, filename pattern, file format).
DATASETS = {
    "agency_actuals": (
        "01_agency_actuals", "01_agency_actuals_*.csv", "csv"),
    "sector_expenditure": (
        "02_sector_expenditure", "02_sector_expenditure_*.csv", "csv"),
    "regional_expenditure_gaa": (
        "03_regional_expenditure", "03_regional_expenditure_gaa_*.csv", "csv"),
    "regional_expenditure_obligations": (
        "03_regional_expenditure", "03_regional_expenditure_obligations_*.csv", "csv"),
    "population": (
        "04_population", "*.csv", "csv"),
    "grdp": (
        "05_development_indicators", "grdp_20*.xlsx", "excel"),
    "grdp_per_capita": (
        "05_development_indicators", "grdp_per_capita_20*.xlsx", "excel"),
}


def ingest(name, folder, pattern, file_format):
    state = f"{ROOT}/_ingestion/{name}"

    # Use reader settings for the dataset's file format.
    options = {
        "cloudFiles.format": file_format,
        "pathGlobFilter": pattern,
        "cloudFiles.schemaLocation": f"{state}/schema",
        "cloudFiles.allowOverwrites": "false",
        "cloudFiles.useIncrementalListing": "false",
    }

    if file_format == "csv":
        options.update({
            "header": "true",
            "multiLine": "true",
            "escape": '"',
            "cloudFiles.schemaEvolutionMode": "rescue",
        })
    elif file_format == "excel":
        options.update({
            "headerRows": "1",
            "cloudFiles.schemaEvolutionMode": "none",
        })
    else:
        raise ValueError(f"Unsupported format: {file_format}")

    # Read files and record their source and ingestion time.
    df = (
        spark.readStream.format("cloudFiles")
        .options(**options)
        .load(f"{ROOT}/source/{folder}")
        .select("*", F.col("_metadata.file_path").alias("_source_file"))
        .withColumn("_ingested_at", F.current_timestamp())
    )

    # Checkpoints prevent processed files from loading again.
    query = (
        df.writeStream.format("delta")
        .outputMode("append")
        .option("checkpointLocation", f"{state}/checkpoint")
        .trigger(availableNow=True)
        .toTable(f"{TARGET}.{name}")
    )

    query.awaitTermination()
    print(f"Completed: {TARGET}.{name}")


spark.sql(f"CREATE SCHEMA IF NOT EXISTS {TARGET}")

for name, config in DATASETS.items():
    ingest(name, *config)