# PondoLens — Philippine Government Budget Analysis

Source-specific extraction, long-form conversion, validation, and local SQLite ingestion for the supplied FY2024–FY2025 DBM/PSA sources. Originals are preserved. Source datasets and generated outputs are not committed to Git.

## What this pipeline produces

`pondolens` preserves originals and extracts all nonempty Excel cells/PDF text into structural JSONL. `pondolens-long` creates separate long-form CSV tables, checks business keys and control totals, and loads passing sources into `outputs/long_form.sqlite`.

These are **validated source tables**, not a completed Databricks or Gold pipeline. Cross-source joins remain blocked until department/agency crosswalks, budget scope, and regional boundaries are reviewed. Agency detail hierarchy remains a separate candidate table. A converter PASS does not make every retained row additive or establish that the original report itself is error-free.

## Existing VS Code project on macOS

If you cloned with Git, open the repository root in VS Code and update the working branch:

```bash
git fetch origin
git switch feature/ingestion-foundation
git pull --ff-only
source .venv/bin/activate
python -m pip install -e '.[dev]'
pytest -q
pondolens-long --raw data/raw --output outputs
pondolens-long --raw data/raw --output outputs
```

If you downloaded the code ZIP, copy its `src/`, `tests/`, `docs/`, `.github/`, `pyproject.toml`, and `README.md` into your existing project. Preserve your `data/`, `outputs/`, and `.venv/`. Then run the commands starting at `source .venv/bin/activate` from the folder containing `pyproject.toml`.

The first run converts the original files. An unchanged second run prints `REUSED conversion`; it verifies saved outputs and rebuilds the SQLite current snapshot without adding duplicates. Run one process at a time. Initial GAA conversion is substantial; watch the `CONVERTING` messages. Do not open large GAA CSVs in Excel: the row counts and text fields can be large, and Excel can alter identifier formatting.

For a new installation:

```bash
git clone https://github.com/ItsYangCoder/ph-government-budget-analysis.git
cd ph-government-budget-analysis
git switch feature/ingestion-foundation
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
pytest -q
```

Use Python 3.11 or newer, Git, VS Code, and the Microsoft Python extension. Select the `.venv` interpreter. Python packages are `openpyxl`, `pdfplumber`, and `pytest` for development. CSV, Decimal, SHA-256, and SQLite use the Python standard library; no additional database server or OCR package is needed for these supplied PDFs.

## Input folders

Keep the nine original files directly under these folders:

| Folder under `data/raw/` | Files | Conversion |
|---|---|---|
| `01_agency_actuals` | 2 Excel | Separate department summary and detail hierarchy candidates; melt financial measures/expense classes |
| `02_approved_gaa` | 2 Excel | Already long; preserve codes, funds, program and object detail; separate final SUM row |
| `03_sector_actuals` | 1 Excel | Seven measures, year columns and growth intervals; actual/program/proposed kept separate |
| `04_regional_actuals` | 2 PDF | Coordinate-based columns; both pages aligned; split digits joined; rotated text excluded |
| `05_population` | 1 Excel | Projected population by year, geography, age and sex; separate growth intervals |
| `06_development_indicator` | 1 Excel | Current/constant prices, growth, and national indices kept separate |

To preserve the initial structural archive, use the original command if you have not already run it:

```bash
pondolens --raw data/raw --output outputs
```

You do not need to rerun structural extraction before every long-form conversion. Long-form conversion reads original files directly. An alternative for an existing complete extraction ZIP is:

```bash
pondolens-long --structure-zip /path/to/pondolens-extraction.zip --output outputs
```

Original and ZIP modes have separate fingerprints. ZIP mode validates record provenance and does not independently recalculate workbook formulas. Never extract the 8+ GB structural ZIP just to run this alternative.

## Outputs and results

| Output | Purpose |
|---|---|
| `outputs/long_form/<run_id>/*.csv` | Long-form rows per source/dataset, including explicit missing/error states and review candidates |
| `outputs/long_form/<run_id>/report.json` | Source statuses, duplicate examples, reconciliation checks, notes and blockers |
| `outputs/long_form/<run_id>/manifest.json` | Input/configuration/code/dependency fingerprints and output checksums |
| `outputs/latest_long_form.json` | Latest successful publication report and output directory |
| `outputs/long_form.sqlite` | Current passing source partitions, source statuses, and SQL views |

`PASS` sources are loaded. `REVIEW_REQUIRED` sources stay in CSV for review and their current database partition is unavailable; an older source version is not silently kept active. Exit code `0` means all source gates passed, `2` means conversion completed with review blockers, and `1` means the command failed. Previous completed generations remain on disk. `ready_for_cross_source_analysis` stays false until the documented join gates are resolved.

The supplied GAA files have verified thousand-peso units, tied to their exact SHA-256 hashes and official Senate appropriation controls. A revised/unrecognized GAA file requires documented units:

```bash
pondolens-long --raw data/raw --output outputs --gaa-unit thousand_PHP --gaa-unit-evidence 'Verified official reference and matching amount control'
```

Do not supply this override without verifying the revised source. Totals and business key validation still run. Unknown units and conflicting overrides block GAA publication.

## Query the current source tables

Use SQLite directly with Python; decimals remain text in the source tables to preserve their representation. Cast explicitly for a query and use Decimal for exact financial reconciliation.

```python
import sqlite3

with sqlite3.connect("outputs/long_form.sqlite") as connection:
    print(connection.execute("SELECT source, status FROM source_status").fetchall())
    print(connection.execute("""
        SELECT year, entity, value, unit
        FROM agency_department_financials
        WHERE measure = 'obligations'
        ORDER BY CAST(value AS REAL) DESC
        LIMIT 10
    """).fetchall())
```

See [long-form schemas and validation rules](docs/long_form.md) and [real-source verification evidence](docs/evidence/long_form_validation.md). These explain safe row selections, idempotency, and the remaining analytical limits.
