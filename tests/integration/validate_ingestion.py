"""Run in Databricks with an active Spark session to compare ingestion outputs."""
from pyspark.sql import functions as F

ORIGINAL = "pondolens.dev_bronze"
REFACTORED = "pondolens.dev_bronze_refactor_tes"

# Original table name → refactored table name.
TABLE_PAIRS = {
    "agency_actuals": "agency_actuals",
    "regional_appropriation": "regional_appropriation",
    "regional_obligations": "regional_obligations",
    "population": "population",
    "unemployment_rate": "unemployment_rate",
    "poverty_incidence": "poverty_incidence",
    "service_access": "service_access",
    "grdp_per_capita": "grdp_per_capita",
    "completion_rate": "completion_rate",
    "region_boundaries": "region_boundaries",
    "hospital": "hospital",
}

results = []

for old_name, new_name in TABLE_PAIRS.items():
    original_table = f"{ORIGINAL}.{old_name}"
    refactored_table = f"{REFACTORED}.{new_name}"

    try:
        if not (
            spark.catalog.tableExists(original_table)
            and spark.catalog.tableExists(refactored_table)
        ):
            results.append((
                new_name, "MISSING_TABLE",
                None, None, None, None,
                "Check original and refactored table names."
            ))
            continue

        original = spark.table(original_table)
        refactored = spark.table(refactored_table)

        # Compare source fields and rescued records.
        # Exclude run-specific and other ingestion metadata.
        def comparison_columns(frame):
            return sorted(
                column for column in frame.columns
                if not column.startswith("_")
                or column == "_rescued_data"
            )

        old_columns = comparison_columns(original)
        new_columns = comparison_columns(refactored)

        old_count = original.count()
        new_count = refactored.count()

        if old_columns != new_columns:
            results.append((
                new_name, "COLUMN_MISMATCH",
                old_count, new_count, None, None,
                f"Only original: {sorted(set(old_columns) - set(new_columns))}; "
                f"only refactored: {sorted(set(new_columns) - set(old_columns))}"
            ))
            continue

        # Bronze source fields are compared as strings.
        def comparable(frame):
            return frame.select(*[
                F.col(f"`{column}`").cast("string").alias(column)
                for column in old_columns
            ])

        old_data = comparable(original)
        new_data = comparable(refactored)

        # EXCEPT ALL preserves duplicate counts.
        original_only = old_data.exceptAll(new_data).count()
        refactored_only = new_data.exceptAll(old_data).count()

        status = (
            "MATCH"
            if original_only == 0 and refactored_only == 0
            else "DIFFERENT"
        )

        results.append((
            new_name, status,
            old_count, new_count,
            original_only, refactored_only, ""
        ))

    except Exception as exc:
        results.append((
            new_name, "ERROR",
            None, None, None, None,
            str(exc)[:500]
        ))

schema = """
    dataset STRING,
    status STRING,
    original_rows BIGINT,
    refactored_rows BIGINT,
    original_only_rows BIGINT,
    refactored_only_rows BIGINT,
    message STRING
"""

display(spark.createDataFrame(results, schema))