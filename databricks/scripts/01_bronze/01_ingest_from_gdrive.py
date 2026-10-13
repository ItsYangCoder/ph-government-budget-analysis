"""PondoLens Google Drive -> Bronze Delta ingestion.

Requires spark, dbutils, Unity Catalog Volume access, and:
google-api-python-client, google-auth, openpyxl.

Default is validation only: set dry_run to false to load.
All source years are preserved.

Each changed dataset is overwritten from ALL its current Drive files.
Existing mapped tables are replaced, including their schema.
Keep the complete source history in Drive.
Tables are committed independently; run only one writer.
"""

import argparse
import csv
import hashlib
import importlib.util
import io
import json
import re
import subprocess
import sys
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

# Install missing packages using the script's Python interpreter.
required_packages = {
    "openpyxl": "openpyxl",
    "googleapiclient": "google-api-python-client",
    "google.auth": "google-auth",
}

missing_packages = []

for module_name, package_name in required_packages.items():
    try:
        available = importlib.util.find_spec(module_name) is not None
    except ModuleNotFoundError:
        available = False

    if not available:
        missing_packages.append(package_name)

if missing_packages:
    subprocess.check_call([
        sys.executable,
        "-m",
        "pip",
        "install",
        *missing_packages,
    ])
    importlib.invalidate_caches()

import openpyxl
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from pyspark.sql import functions as F
from pyspark.sql.types import (
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)


DATASET_NAMES = [
    "agency_actuals",
    "sector_expenditure",
    "regional_expenditure_gaa",
    "regional_expenditure_obligations",
    "population",
    "ched_graduates",
    "unemployment_rate",
    "poverty_incidence",
    "service_access",
    "grdp",
    "grdp_per_capita",
]

DEFAULTS = {
    "catalog": "pondolens",
    "schema": "dev_bronze",
    "volume": "government_budget",
    "drive_folder_id": "1L_kvzPjQE60GjUvthLuwxbC3xKevHsoB",
    "secret_scope": "pondolens",
    "secret_key": "gdrive-service-account",
    "dataset": "all",
    "dry_run": "true",
    "sheet_overrides_json": "{}",
}


def parameters():
    # Notebook widgets and Job script arguments use the same names.
    parser = argparse.ArgumentParser()

    for name, default in DEFAULTS.items():
        parser.add_argument(f"--{name}", default=default)

    arguments, _ = parser.parse_known_args()

    if any(
        arg.split("=")[0] == f"--{name}"
        for arg in sys.argv[1:]
        for name in DEFAULTS
    ):
        result = vars(arguments)
    else:
        try:
            for name, default in DEFAULTS.items():
                if name == "dry_run":
                    dbutils.widgets.dropdown(
                        name, default, ["true", "false"]
                    )
                elif name == "dataset":
                    dbutils.widgets.dropdown(
                        name, default, ["all"] + DATASET_NAMES
                    )
                else:
                    dbutils.widgets.text(name, default)

            result = {
                name: dbutils.widgets.get(name).strip()
                for name in DEFAULTS
            }

        except (AttributeError, NotImplementedError):
            result = vars(arguments)

    if result["dry_run"] not in {"true", "false"}:
        raise ValueError("dry_run must be true or false")

    if result["dataset"] not in ["all"] + DATASET_NAMES:
        raise ValueError("Unknown dataset parameter")

    if not re.fullmatch(
        r"[A-Za-z0-9_-]+", result["drive_folder_id"]
    ):
        raise ValueError(
            "drive_folder_id must be a folder ID, not a URL"
        )

    return result


PARAMS = parameters()

CATALOG = PARAMS["catalog"]
SCHEMA = PARAMS["schema"]
VOLUME = PARAMS["volume"]
DRIVE_FOLDER_ID = PARAMS["drive_folder_id"]
SECRET_SCOPE = PARAMS["secret_scope"]
SECRET_KEY = PARAMS["secret_key"]
DRY_RUN = PARAMS["dry_run"] == "true"
SELECTED_DATASET = PARAMS["dataset"]


# Optional worksheet overrides, keyed by Drive file ID.
# Otherwise select one long-form tab by name or header.
SHEET_OVERRIDES = {
    "1vCXocazfgtHpey2wG6sTzpQFI-pBrDfF": "Long Form",
}

custom_sheets = json.loads(PARAMS["sheet_overrides_json"])

if not isinstance(custom_sheets, dict) or any(
    not isinstance(k, str) or not isinstance(v, str)
    for k, v in custom_sheets.items()
):
    raise ValueError(
        "sheet_overrides_json must map file IDs to sheet names"
    )

SHEET_OVERRIDES.update(custom_sheets)

RUN_ID = uuid.uuid4().hex

FOLDER_MIME = "application/vnd.google-apps.folder"
SHEET_MIME = "application/vnd.google-apps.spreadsheet"
XLSX_MIME = (
    "application/vnd.openxmlformats-officedocument."
    "spreadsheetml.sheet"
)

PIPELINE_VERSION = "gdrive-snapshot-1"


def identifier(value):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        raise ValueError(f"Invalid identifier: {value!r}")

    return value


TARGET = f"{identifier(CATALOG)}.{identifier(SCHEMA)}"
ROOT = f"/Volumes/{CATALOG}/{SCHEMA}/{identifier(VOLUME)}"


def route(relative_path):
    """Route known long-form folders; new years need no edits."""
    parts = relative_path.lower().split("/")
    name = parts[-1]

    if parts[0] == "01_agency_actuals":
        return "agency_actuals"

    if parts[0] == "02_sector_expenditure":
        return "sector_expenditure"

    if parts[0] == "03_regional_expenditure":
        if "gaa" in name:
            return "regional_expenditure_gaa"

        if "obligation" in name:
            return "regional_expenditure_obligations"

    if parts[0] == "04_population":
        return "population"

    indicators = {
        "01_quality_education": "ched_graduates",
        "02_unemployment_rate": "unemployment_rate",
        "03_poverty_incidence": "poverty_incidence",
        "04_service_access": "service_access",
        "05_grdp": "grdp",
        "06_grdp_capita": "grdp_per_capita",
    }

    if (
        parts[0] == "05_development_indicators"
        and len(parts) > 2
    ):
        return indicators.get(parts[1])

    return None


def list_children(drive, folder_id):
    token = None

    while True:
        response = drive.files().list(
            q=f"'{folder_id}' in parents and trashed = false",
            pageSize=1000,
            pageToken=token,
            fields=(
                "nextPageToken,"
                "files(id,name,mimeType,modifiedTime,size)"
            ),
            supportsAllDrives=True,
            includeItemsFromAllDrives=True,
        ).execute(num_retries=3)

        yield from response.get("files", [])

        token = response.get("nextPageToken")

        if not token:
            break


def walk(drive, folder_id, prefix="", visited=None):
    visited = set() if visited is None else visited

    if folder_id in visited:
        raise ValueError("Repeated folder in traversal")

    visited.add(folder_id)

    for item in sorted(
        list_children(drive, folder_id),
        key=lambda x: x["name"],
    ):
        relative = prefix + item["name"]

        if item["mimeType"] == FOLDER_MIME:
            yield from walk(
                drive,
                item["id"],
                relative + "/",
                visited,
            )
        else:
            yield {**item, "relative_path": relative}


def download(drive, item):
    if item["mimeType"] == SHEET_MIME:
        request = drive.files().export_media(
            fileId=item["id"],
            mimeType=XLSX_MIME,
        )
    else:
        request = drive.files().get_media(
            fileId=item["id"],
            supportsAllDrives=True,
        )

    buffer = io.BytesIO()
    downloader = MediaIoBaseDownload(buffer, request)
    done = False

    while not done:
        _, done = downloader.next_chunk(num_retries=3)

    after = drive.files().get(
        fileId=item["id"],
        fields="modifiedTime",
        supportsAllDrives=True,
    ).execute(num_retries=3)

    if after["modifiedTime"] != item["modifiedTime"]:
        raise RuntimeError(
            f"File changed during download: "
            f"{item['relative_path']}"
        )

    return buffer.getvalue()


def clean_header(row):
    result = []

    for index, value in enumerate(row):
        label = str(value).strip() if value is not None else ""
        label = re.sub(
            r"[^A-Za-z0-9_]", "_", label
        ).strip("_").lower()

        label = label or f"source_column_{index + 1}"

        if label[0].isdigit():
            label = "c_" + label

        if label.startswith("_") or label in result:
            raise ValueError(
                f"Duplicate/reserved header: {label}"
            )

        result.append(label)

    return result


def read_rows(item, payload):
    name = item["name"].lower()

    if name.endswith(".csv"):
        rows = list(
            csv.reader(
                io.StringIO(payload.decode("utf-8-sig")),
                strict=True,
            )
        )
        sheet = None

    else:
        workbook = openpyxl.load_workbook(
            io.BytesIO(payload),
            read_only=True,
            data_only=True,
        )

        try:
            sheet = SHEET_OVERRIDES.get(item["id"])

            if not sheet:
                candidates = []

                for ws in workbook.worksheets:
                    header = next(
                        ws.iter_rows(values_only=True), ()
                    )

                    labels = {
                        str(v).strip().lower()
                        for v in header
                        if v is not None
                    }

                    long_name = re.sub(
                        r"[^a-z]", "", ws.title.lower()
                    ) in {
                        "longform",
                        "longdata",
                        "populationlong",
                        "graduateslong",
                    }

                    year_header = bool(
                        labels & {
                            "year",
                            "fiscal_year",
                            "reference_year",
                            "academic_year",
                        }
                    )

                    if long_name or year_header:
                        candidates.append(ws.title)

                if len(candidates) != 1:
                    raise ValueError(
                        f"Select a tab in SHEET_OVERRIDES "
                        f"for {item['name']}; "
                        f"tabs={workbook.sheetnames}, "
                        f"candidates={candidates}"
                    )

                sheet = candidates[0]

            rows = list(
                workbook[sheet].iter_rows(values_only=True)
            )

        finally:
            workbook.close()

    if not rows:
        raise ValueError(f"Empty source: {item['name']}")

    headers = clean_header(rows[0])
    records = []

    for number, row in enumerate(rows[1:], start=2):
        if not any(
            value is not None and str(value) != ""
            for value in row
        ):
            continue

        values = tuple(
            None if value is None else str(value)
            for value in row
        )
        rescued = None

        if len(values) != len(headers):
            rescued = json.dumps(
                {
                    "reason": "column_count_mismatch",
                    "source_file": item["relative_path"],
                    "source_row": number,
                    "expected_columns": len(headers),
                    "actual_columns": len(values),
                    "headers": headers,
                    "original_values": values,
                },
                ensure_ascii=False,
            )

            # Preserve the original row without guessing column positions.
            values = (None,) * len(headers)

        records.append(values + (rescued,))

    if not records:
        raise ValueError(
            f"Source has no data rows: {item['name']}"
        )

    return (
        headers + ["_rescued_data"],
        records,
        sheet,
        dict(zip(headers, map(str, rows[0]))),
    )


def log(
    dataset,
    status,
    count,
    message=None,
    files_loaded=0,
    started_at=None,
    rescued_rows=0,
):
    record = {
        "run_id": RUN_ID,
        "dataset": dataset,
        "status": status,
        "rows_loaded": str(count),
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "message": message or "",
        "files_loaded": files_loaded,
        "rescued_rows": rescued_rows,
        "started_at": started_at,
    }

    # Preserve existing column types; type only the new fields.
    audit_types = {
        "files_loaded": LongType(),
        "rescued_rows": LongType(),
        "started_at": TimestampType(),
    }

    schema = StructType([
        StructField(
            key,
            audit_types.get(key, StringType()),
            True,
        )
        for key in record
    ])

    (
        spark.createDataFrame(
            [tuple(record.values())],
            schema,
        )
        .write.format("delta")
        .mode("append")
        .option("mergeSchema", "true")
        .saveAsTable(f"{TARGET}.gdrive_ingestion_log")
    )


def main():
    credentials = (
        service_account.Credentials.from_service_account_info(
            json.loads(
                dbutils.secrets.get(
                    scope=SECRET_SCOPE,
                    key=SECRET_KEY,
                )
            ),
            scopes=[
                "https://www.googleapis.com/auth/drive.readonly"
            ],
        )
    )

    drive = build(
        "drive",
        "v3",
        credentials=credentials,
        cache_discovery=False,
    )

    drive.files().get(
        fileId=DRIVE_FOLDER_ID,
        fields="id,name",
        supportsAllDrives=True,
    ).execute(num_retries=3)

    if not DRY_RUN:
        # Require the existing Volume.
        dbutils.fs.ls(ROOT)

    sources = list(walk(drive, DRIVE_FOLDER_ID))
    plans = defaultdict(list)
    errors = []

    # Validate ALL files before any table writes.
    for item in sources:
        dataset = route(item["relative_path"])

        if (
            SELECTED_DATASET != "all"
            and dataset != SELECTED_DATASET
        ):
            continue

        supported = (
            item["mimeType"] == SHEET_MIME
            or item["name"].lower().endswith(
                (".csv", ".xlsx", ".xlsm")
            )
        )

        if not dataset or not supported:
            errors.append(
                "Unmapped/unsupported source: "
                f"{item['relative_path']}"
            )
            continue

        try:
            payload = download(drive, item)

            headers, records, sheet, header_map = read_rows(
                item, payload
            )

            digest = hashlib.sha256(payload).hexdigest()

            plans[dataset].append((
                item,
                payload,
                headers,
                records,
                sheet,
                digest,
                header_map,
            ))

            print(
                f"VALID {dataset}: {item['relative_path']} "
                f"rows={len(records)} tab={sheet}"
            )

        except Exception as exc:
            errors.append(
                f"{item['relative_path']}: {exc}"
            )

    if not sources:
        errors.append("No sources found in Drive folder")

    if not plans and not errors:
        errors.append(
            "No files found for selected dataset: "
            f"{SELECTED_DATASET}"
        )

    if errors:
        raise ValueError(
            "Validation failed; no tables written:\n"
            + "\n".join(errors)
        )

    file_count = sum(
        len(entries) for entries in plans.values()
    )

    print(
        f"Plan: {file_count} files -> {len(plans)} tables; "
        f"dry_run={DRY_RUN}"
    )

    if DRY_RUN:
        return

    spark.sql(f"CREATE SCHEMA IF NOT EXISTS {TARGET}")

    failures = []

    for dataset, entries in sorted(plans.items()):
        # Audit timing starts before the dataset load/skip check.
        started_at = datetime.now(timezone.utc)
        files_loaded = 0
        rescued_rows = 0

        table = f"{TARGET}.{identifier(dataset)}"
        count = sum(len(entry[3]) for entry in entries)

        fingerprint = hashlib.sha256(
            json.dumps(
                [
                                       (
                        entry[0]["id"],
                        entry[0]["relative_path"],
                        (
                            hashlib.sha256(
                                json.dumps(
                                    {
                                        "headers": entry[2],
                                        "records": entry[3],
                                        "sheet": entry[4],
                                        "header_map": entry[6],
                                    },
                                    ensure_ascii=False,
                                    sort_keys=True,
                                    separators=(",", ":"),
                                ).encode("utf-8")
                            ).hexdigest()
                            if entry[0]["mimeType"] == SHEET_MIME
                            else entry[5]
                        ),
                        entry[4],
                    )
                    for entry in sorted(
                        entries,
                        key=lambda e: e[0]["id"],
                    )
                ] + [PIPELINE_VERSION],
                sort_keys=True,
            ).encode()
        ).hexdigest()

        try:
            if spark.catalog.tableExists(table):
                current = spark.table(table)

                if "_dataset_hash" in current.columns:
                    hashes = [
                        r[0]
                        for r in (
                            current.select("_dataset_hash")
                            .distinct()
                            .collect()
                        )
                    ]

                    if (
                        "_rescued_data" in current.columns
                        and hashes == [fingerprint]
                        and current.count() == count
                    ):
                        print(
                            f"SKIPPED {table}: "
                            "unchanged source content"
                        )

                        log(
                            dataset,
                            "SKIPPED",
                            0,
                            files_loaded=0,
                            started_at=started_at,
                        )
                        continue

            combined = None

            for (
                item,
                payload,
                headers,
                records,
                sheet,
                digest,
                header_map,
            ) in entries:
                extension = (
                    ".csv"
                    if item["name"].lower().endswith(".csv")
                    else ".xlsx"
                )

                path = (
                    Path(ROOT)
                    / "gdrive_landing"
                    / item["id"]
                    / (digest + extension)
                )

                path.parent.mkdir(
                    parents=True,
                    exist_ok=True,
                )
                path.write_bytes(payload)

                schema = StructType([
                    StructField(c, StringType(), True)
                    for c in headers
                ])

                frame = spark.createDataFrame(
                    records, schema
                )

                for column, value in {
                    "_drive_file_id": item["id"],
                    "_source_file": item["relative_path"],
                    "_landing_file": str(path),
                    "_source_modified_at": item["modifiedTime"],
                    "_source_sheet": sheet,
                    "_content_hash": digest,
                    "_header_map": json.dumps(header_map),
                    "_dataset_hash": fingerprint,
                    "_run_id": RUN_ID,
                }.items():
                    frame = frame.withColumn(
                        column,
                        F.lit(value).cast("string"),
                    )

                frame = frame.withColumn(
                    "_ingested_at",
                    F.current_timestamp(),
                )

                combined = (
                    frame
                    if combined is None
                    else combined.unionByName(
                        frame,
                        allowMissingColumns=True,
                    )
                )

            # Full dataset snapshot.
            (
                combined.write.format("delta")
                .mode("overwrite")
                .option("overwriteSchema", "true")
                .saveAsTable(table)
            )

            files_loaded = len(entries)
            actual = spark.table(table).count()

            rescued_rows = (
                spark.table(table)
                .where(F.col("_rescued_data").isNotNull())
                .count()
            )

            if actual != count:
                raise RuntimeError(
                    f"Row count mismatch: expected={count}, "
                    f"actual={actual}"
                )

            log(
                dataset,
                "SUCCESS",
                actual,
                files_loaded=files_loaded,
                started_at=started_at,
                rescued_rows=rescued_rows,
            )

            print(
                f"SUCCESS {table}: "
                f"files={len(entries)} rows={actual}"
            )

        except Exception as exc:
            failures.append(f"{dataset}: {exc}")

            try:
                log(
                    dataset,
                    "FAILED",
                    0,
                    str(exc)[:2000],
                    files_loaded=files_loaded,
                    started_at=started_at,
                    rescued_rows=rescued_rows,
                )

            except Exception as log_error:
                print(
                    f"Log failed for {dataset}: {log_error}"
                )

    if failures:
        raise RuntimeError(
            "Some datasets failed; rerun after fixing:\n"
            + "\n".join(failures)
        )

    print(
        f"Completed run {RUN_ID}. "
        f"Log: {TARGET}.gdrive_ingestion_log"
    )


if __name__ == "__main__":
    main()