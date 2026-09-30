"""Convert source-specific long tables and publish validated local SQLite partitions."""

import argparse
from collections import Counter
from contextlib import ExitStack, closing, contextmanager
import csv
from decimal import Decimal
import hashlib
from importlib.metadata import version as package_version
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import tempfile
import zipfile

from .converters import excel, regional
from .converters.common import Controls, effective, excel_rows, number, record, rows_from_records
from .ingestion import EXPECTED, digest, discover, pdf_records

VERSION = "long-form-v1"
CONVERTERS = {"01_agency_actuals": excel.agency, "02_approved_gaa": excel.gaa,
              "03_sector_actuals": excel.sector, "04_regional_actuals": regional.regional,
              "05_population": excel.population, "06_development_indicator": excel.grdp}
DATASETS = ["agency_summary", "agency_detail_candidates", "approved_budget", "approved_budget_controls", "sector_expenditure",
            "regional_actuals", "population_projection", "population_growth", "development_indicator"]
DATASETS.append("source_numeric_candidates")
COLUMNS = ["dataset", "record_key", "source", "source_sha256", "converter_version", "year", "period",
           "entity", "parent_entity", "department_code", "department", "agency_code", "program_code",
           "program_level", "program", "operating_unit", "operating_unit_name", "region_code", "region",
           "division_code", "division", "fund_code", "fund", "expense_code", "expense_class",
           "subobject_code", "subobject", "source_order", "province", "geo_level", "age_group", "sex",
           "section", "measure", "record_level", "reporting_basis", "status", "price_basis", "geography_basis",
           "unit", "value", "value_php", "value_status", "analytical_eligible", "source_table", "source_page",
           "source_row", "source_column", "raw_value", "original_formula"]
BAD_VALUES = {"source_excel_error", "invalid_numeric", "invalid_domain", "missing_formula_cache", "missing"}


def write_json(path, content):
    descriptor, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(content, stream, ensure_ascii=False, indent=2)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


@contextmanager
def run_lock(output):
    path = output / ".long_form.lock"
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise RuntimeError("Another long-form run holds outputs/.long_form.lock. Remove it only after confirming that process stopped.") from exc
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(str(os.getpid()))
        yield
    finally:
        path.unlink(missing_ok=True)


def raw_inputs(root):
    result = []
    for path in discover(root):
        result.append(dict(source=path.relative_to(root).as_posix(), sha256=digest(path), path=str(path)))
    return result


def zip_inputs(archive):
    result = []
    seen = set()
    for name in archive.namelist():
        if not name.endswith(".jsonl"):
            continue
        with archive.open(name) as stream:
            first = json.loads(stream.readline())
        source = first["source"]
        if not re.fullmatch(r"[0-9a-f]{64}", first.get("sha256", "")):
            raise ValueError("Invalid source SHA-256 in extraction ZIP")
        if source in seen or source.split("/")[0] not in EXPECTED:
            raise ValueError("Duplicate or unknown structural source")
        if first["parser_version"] != "raw-structure-v1":
            raise ValueError("Unsupported structural parser version")
        seen.add(source)
        result.append(dict(source=source, sha256=first["sha256"], member=name))
    counts = Counter(x["source"].split("/")[0] for x in result)
    if counts != Counter({folder: spec[1] for folder, spec in EXPECTED.items()}):
        raise ValueError("Structural ZIP must contain the nine expected sources")
    return sorted(result, key=lambda x: x["source"])


def read_input(item, archive):
    if archive is None:
        if item["source"].endswith(".pdf"):
            return (r for r in pdf_records(item["path"]) if r["kind"] == "pdf_page")
        return excel_rows(item["path"])

    def records():
        with archive.open(item["member"]) as stream:
            for line in stream:
                record = json.loads(line)
                if (record.get("source"), record.get("sha256"), record.get("parser_version")) != (
                        item["source"], item["sha256"], "raw-structure-v1"):
                    raise ValueError("Structural provenance mismatch")
                yield record
    if item["source"].endswith(".pdf"):
        return (r for r in records() if r["kind"] == "pdf_page")
    return rows_from_records(records())


def convert_source(item, archive, config, staging):
    controls = Controls()
    counts, value_counts = Counter(), Counter()
    duplicates = []
    duplicate_count = bad_count = 0
    filenames = {}
    years = set()
    pending_cells = {}

    def source_rows():
        for sheet, row_number, cells in read_input(item, archive):
            for column, cell in cells.items():
                if number(effective(cell))[1] in {"ok", "source_excel_error"} or cell.get("missing_formula_cache"):
                    pending_cells[(sheet, row_number, column)] = cell
            yield sheet, row_number, cells

    def converted_rows():
        converter = CONVERTERS[item["source"].split("/")[0]]
        track_cells = item["source"].endswith(".xlsx") and "02_approved_gaa/" not in item["source"]
        reader = source_rows() if track_cells else read_input(item, archive)
        for converted in converter(reader, controls, dict(config, source=item["source"], source_sha256=item["sha256"])):
            pending_cells.pop((converted["source_table"], converted["source_row"], converted["source_column"]), None)
            yield converted
        if pending_cells:
            controls.notes.append(f"{len(pending_cells)} remaining numeric/header/support cells retained in source_numeric_candidates; excluded from analytical views.")
        for (sheet, row_number, column), cell in pending_cells.items():
            yield record("source_numeric_candidates", sheet, row_number, column, cell,
                         unit="source_unmapped", key=[item["source"], sheet, row_number, column], eligible=False,
                         measure="unmapped_source_numeric", record_level="source_cell")
    # Disk-backed business key checks keep memory bounded for large GAA sources.
    with ExitStack() as stack:
        key_db = stack.enter_context(closing(sqlite3.connect(":memory:" if "02_approved_gaa" not in item["source"]
                                                           else str(staging / "keys.sqlite"))))
        key_db.execute("CREATE TABLE IF NOT EXISTS keys (dataset TEXT, key TEXT, PRIMARY KEY(dataset,key))")
        key_db.execute("DELETE FROM keys")
        writers = {}
        try:
            for row in converted_rows():
                dataset = row["dataset"]
                if row["unit"] == "persons" and row["value_status"] == "ok":
                    amount = Decimal(row["value"])
                    if amount < 0 or amount != amount.to_integral_value():
                        row["value_status"] = "invalid_domain"
                if dataset not in writers:
                    filename = f"{item['sha256'][:16]}-{dataset}.csv"
                    filenames[dataset] = filename
                    stream = stack.enter_context((staging / filename).open("w", encoding="utf-8", newline=""))
                    writers[dataset] = csv.DictWriter(stream, fieldnames=COLUMNS)
                    writers[dataset].writeheader()
                try:
                    key_db.execute("INSERT INTO keys VALUES (?, ?)", (dataset, row["record_key"]))
                except sqlite3.IntegrityError:
                    duplicate_count += 1
                    if len(duplicates) < 20:
                        duplicates.append({k: row[k] for k in ["dataset", "record_key", "source_table", "source_row", "source_column"]})
                counts[dataset] += 1
                if row.get("year") is not None:
                    years.add(row["year"])
                value_counts[row["value_status"]] += 1
                # Regional printed blank cells are explicit source states, not invented zeros.
                if row["analytical_eligible"] and row["value_status"] in BAD_VALUES:
                    if not (dataset == "regional_actuals" and row["value_status"] == "missing"):
                        bad_count += 1
                row.update(source=item["source"], source_sha256=item["sha256"], converter_version=VERSION)
                row["analytical_eligible"] = "1" if row["analytical_eligible"] else "0"
                writers[dataset].writerow(row)
        except Exception as exc:
            controls.blockers.append(f"Conversion failed: {type(exc).__name__}: {exc}")
        if archive is None:
            controls.require(digest(item["path"]) == item["sha256"], "Source changed during conversion; rerun from a stable original")
    (staging / "keys.sqlite").unlink(missing_ok=True)
    failed_checks = sum(not c["passed"] for c in controls.checks)
    controls.require(bool(counts), "No long-form rows produced")
    if duplicate_count:
        controls.blockers.append(f"{duplicate_count} duplicate business keys; retained in CSV for review, not automatically removed")
    if bad_count:
        controls.blockers.append(f"{bad_count} invalid analytical values")
    if failed_checks:
        controls.blockers.append(f"{failed_checks} reconciliation checks failed")
    return dict(source=item["source"], source_sha256=item["sha256"],
                status="PASS" if not controls.blockers else "REVIEW_REQUIRED", counts=dict(counts),
                years=sorted(years),
                value_states=dict(value_counts), files=filenames, duplicate_count=duplicate_count,
                duplicate_examples=duplicates, checks=controls.checks, blockers=controls.blockers, notes=controls.notes)


def publish_sqlite(output, directory, report):
    """Replace the current snapshot atomically; blocked revisions cannot leave stale rows active."""
    with closing(sqlite3.connect(output / "long_form.sqlite")) as db:
        with db:
            db.execute("CREATE TABLE IF NOT EXISTS publication (id INTEGER PRIMARY KEY CHECK(id=1), run_id TEXT)")
            db.execute("CREATE TABLE IF NOT EXISTS source_status (source TEXT PRIMARY KEY, status TEXT, report TEXT)")
            db.execute("DELETE FROM source_status")
            definitions = ", ".join(f'"{c}" TEXT' for c in COLUMNS)
            marks = ",".join("?" for _ in COLUMNS)
            for dataset in DATASETS:
                db.execute(f'CREATE TABLE IF NOT EXISTS "{dataset}" ({definitions}, PRIMARY KEY(source, record_key))')
                db.execute(f'DELETE FROM "{dataset}"')
                # Views contain only mapped rows from passing sources, with actual numeric values.
                db.execute(f'DROP VIEW IF EXISTS "validated_{dataset}"')
                db.execute(f'CREATE VIEW "validated_{dataset}" AS SELECT * FROM "{dataset}" '
                           "WHERE analytical_eligible = '1' AND value_status = 'ok'")
            for source in report["sources"]:
                db.execute("INSERT INTO source_status VALUES (?, ?, ?)",
                           (source["source"], source["status"], json.dumps(source)))
                if source["status"] != "PASS":
                    continue
                for dataset, filename in source["files"].items():
                    with (directory / filename).open(encoding="utf-8", newline="") as stream:
                        reader = csv.DictReader(stream)
                        db.executemany(f'INSERT INTO "{dataset}" VALUES ({marks})',
                                       ([row[c] for c in COLUMNS] for row in reader))
            db.execute("INSERT INTO publication VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET run_id=excluded.run_id",
                       (report["run_id"],))
            # Fixed-grain views exclude totals, supporting breakdowns, and overlapping population tables.
            view_queries = {
                "agency_department_financials": "SELECT * FROM validated_agency_summary WHERE record_level = 'department_or_fund' AND section = 'departments' AND expense_class = 'TOTAL'",
                "sector_actual_financials": "SELECT * FROM validated_sector_expenditure WHERE record_level = 'sector' AND measure = 'expenditure' AND status = 'actual'",
                "regional_department_financials": "SELECT * FROM validated_regional_actuals WHERE record_level = 'department_or_fund' AND section = 'DEPARTMENTS' AND region != 'TOTAL'",
                "regional_population_totals": "SELECT * FROM validated_population_projection WHERE source_table = 'Table 4' AND geo_level = 'region' AND sex = 'Both sexes' AND age_group = 'Total'",
                "regional_grdp_current_prices": "SELECT * FROM validated_development_indicator WHERE record_level = 'region' AND measure = 'per_capita_grdp' AND price_basis = 'current'",
            }
            for name, query in view_queries.items():
                db.execute(f'DROP VIEW IF EXISTS "{name}"')
                db.execute(f'CREATE VIEW "{name}" AS {query}')


def code_fingerprint():
    root = Path(__file__).parent
    files = [root / "long_form.py", root / "ingestion.py", *sorted((root / "converters").glob("*.py"))]
    return hashlib.sha256("|".join(digest(p) for p in files).encode()).hexdigest()


def check_source_coverage(results):
    for folder in ["01_agency_actuals", "02_approved_gaa", "04_regional_actuals"]:
        members = [r for r in results if r["source"].startswith(folder + "/")]
        if len(members) != 2:
            continue  # Production discovery enforces counts; isolated converter tests may supply one source.
        valid = sorted(r["years"] for r in members) == [[2024], [2025]]
        hashes = {r["source_sha256"] for r in members}
        if not valid or len(hashes) != 2:
            for source in members:
                source["status"] = "REVIEW_REQUIRED"
                source["blockers"].append("Expected distinct FY2024 and FY2025 inputs; duplicate file/year or missing year detected")


def run(raw_root="data/raw", output_root="outputs", *, structure_zip=None, gaa_unit=None, gaa_unit_evidence=None):
    output = Path(output_root).resolve()
    raw = Path(raw_root).resolve()
    if output == raw or raw in output.parents or output in raw.parents:
        raise ValueError("Raw and output directories must be separate and not nested")
    if gaa_unit and gaa_unit not in {"PHP", "thousand_PHP", "million_PHP"}:
        raise ValueError("Unsupported GAA unit")
    output.mkdir(parents=True, exist_ok=True)
    with run_lock(output), ExitStack() as stack:
        archive = stack.enter_context(zipfile.ZipFile(structure_zip)) if structure_zip else None
        sources = zip_inputs(archive) if archive else raw_inputs(raw)
        config = dict(gaa_unit=gaa_unit, gaa_unit_evidence=gaa_unit_evidence)
        signature = dict(version=VERSION, code_fingerprint=code_fingerprint(),
                         dependencies={p: package_version(p) for p in ["openpyxl", "pdfplumber"]},
                         sources=[[i["source"], i["sha256"]] for i in sources],
                         config=config, input_mode="structure" if archive else "originals",
                         structure_zip_sha256=digest(structure_zip) if archive else None)
        run_id = hashlib.sha256(json.dumps(signature, sort_keys=True).encode()).hexdigest()
        root = output / "long_form"
        root.mkdir(exist_ok=True)
        directory = root / run_id
        manifest_path = directory / "manifest.json"
        reused = False
        if manifest_path.exists():
            try:
                manifest = json.loads(manifest_path.read_text())
                reused = (manifest["signature"] == signature and "report.json" in manifest["checksums"] and
                          all(Path(name).name == name and (directory / name).is_file() and
                              digest(directory / name) == checksum for name, checksum in manifest["checksums"].items()))
            except (OSError, ValueError, KeyError, TypeError, AttributeError):
                reused = False
        if reused:
            report = json.loads((directory / "report.json").read_text())
        else:
            staging = Path(tempfile.mkdtemp(prefix="pending-", dir=root))
            try:
                results = []
                for item in sources:
                    print(f"CONVERTING: {item['source']}", flush=True)
                    result = convert_source(item, archive, config, staging)
                    results.append(result)
                    print(f"{result['status']}: {sum(result['counts'].values()):,} long rows", flush=True)
                check_source_coverage(results)
                report = dict(run_id=run_id, converter_version=VERSION, input_mode=signature["input_mode"],
                              code_fingerprint=signature["code_fingerprint"],
                              ready_for_source_tables=all(s["status"] == "PASS" for s in results),
                              ready_for_cross_source_analysis=False, sources=results,
                              join_blockers=["Department/agency crosswalk and reporting scope require review.",
                                             "Regional boundaries differ, including NIR/Sulu; no automatic geographic joins."])
                write_json(staging / "report.json", report)
                checksums = {p.name: digest(p) for p in staging.iterdir() if p.is_file()}
                write_json(staging / "manifest.json", dict(signature=signature, checksums=checksums))
                if directory.exists():
                    shutil.rmtree(directory)
                os.replace(staging, directory)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        # Rebuild the published snapshot even on reuse, repairing missing/corrupt database contents.
        publish_sqlite(output, directory, report)
        latest = dict(report, output_directory=str(directory), reused_conversion=reused)
        write_json(output / "latest_long_form.json", latest)
        return latest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", default="data/raw")
    parser.add_argument("--output", default="outputs")
    parser.add_argument("--structure-zip", help="Use an existing nine-source structural extraction ZIP")
    parser.add_argument("--gaa-unit", choices=["PHP", "thousand_PHP", "million_PHP"])
    parser.add_argument("--gaa-unit-evidence", help="Verified source reference supporting AMT units")
    args = parser.parse_args()
    try:
        result = run(args.raw, args.output, structure_zip=args.structure_zip,
                     gaa_unit=args.gaa_unit, gaa_unit_evidence=args.gaa_unit_evidence)
    except (ValueError, OSError, RuntimeError, sqlite3.Error, zipfile.BadZipFile) as exc:
        parser.exit(1, f"ERROR: {exc}\n")
    print("REUSED conversion" if result["reused_conversion"] else "Conversion saved")
    for source in result["sources"]:
        print(f"{source['status']}: {source['source']}")
        for blocker in source["blockers"]:
            print(f"  REVIEW: {blocker}")
    print(f"Report: {Path(args.output) / 'latest_long_form.json'}")
    print("Only PASS source partitions are loaded in long_form.sqlite. Cross-source joins remain gated.")
    if not result["ready_for_source_tables"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
