# Setup and verification

Use Python 3.12 in a VS Code terminal. Install the project with `python -m pip install -e '.[dev]'`; this installs openpyxl, pdfplumber, pytest and both CLI commands. CSV, JSON, hashing, decimal arithmetic and SQLite use Python's standard library.

## Input layout

Keep the original files unchanged under `data/raw/`:

| Folder | Files |
|---|---|
| `01_agency_actuals/` | `FY 2024 SAAODB as of December 31, 2024 (FINAL).xlsx`; `FY 2025 SAODB- FINAL FOR POSTING.xlsx` |
| `02_approved_gaa/` | `GAA-2024.xlsx`; `GAA-2025.xlsx` |
| `03_sector_actuals/` | `F.2 By Sector, 1983-2027 (1).xlsx` |
| `04_regional_actuals/` | `2024_B6a.pdf`; `2025_B6a.pdf` |
| `05_population/` | `Statistical Tables (2020 CBPP Subnational).xlsx` |
| `06_development_indicator/` | `02GRDP_PerCapita_2025.xlsx` |

The current discovery contract expects this nine-source layout. Additional years or formats require converter and contract updates.

## Run

```bash
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m pytest -q
pondolens-long --raw data/raw --output outputs
pondolens-long --raw data/raw --output outputs
python -m json.tool outputs/latest_long_form.json
```

Check each source's status, blockers, duplicate count and control results. An unchanged rerun should reuse conversion. `ready_for_cross_source_analysis` remains false while mapping and scope review are pending. Compare source values and report checks before using analytical tables.

For a separate structural extraction, run:

```bash
pondolens --raw data/raw --output outputs
```

This preserves original copies and extracts nonempty workbook cells/PDF text to JSONL. Structural extraction alone is not an analytical table.

## Common issues

| Issue | Action |
|---|---|
| `pondolens-long: command not found` | Activate the project venv and reinstall from the folder containing `pyproject.toml` |
| Missing or unexpected sources | Check the input layout and the error message |
| `REVIEW_REQUIRED` | Inspect blockers; resolve the source or mapping issue before analysis |
| Existing run lock | Confirm no pipeline process is active before removing `outputs/.long_form.lock` |
| Excel header/footer warning | Formatting metadata is ignored; inspect conversion status and data checks separately |

Run one pipeline process at a time. Keep original files and required audit artifacts in managed storage; generated JSONL/CSV/SQLite files do not belong in Git. Do not delete an audit artifact merely because conversion passed.
