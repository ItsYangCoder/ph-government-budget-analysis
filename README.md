# PondoLens — Philippine Government Budget Analysis

FY2024–FY2025 analysis of agency appropriations and obligations, sector cash-based expenditures, and regional obligations with population and economic context.

## Current implementation

This branch provides **local raw ingestion and structural extraction** of the nine original source files. It does not yet implement validated analytical conversion, Silver/Gold tables, or Databricks ingestion. No government source files are committed to Git.

- Preserves complete original bytes in a SHA-256 archive.
- Extracts every nonempty Excel cell from every worksheet to JSONL, including source coordinates, original formula, cached formula result, and number format. Blank cells and workbook formatting remain available in the original archive.
- Extracts PDF page text, word positions, and automatically detected table candidates. Candidates are unvalidated and may be incomplete; scanned pages are flagged for OCR review. No OCR is performed automatically.
- Uses source-relative path + content hash + parser version for idempotency. Successful unchanged outputs are skipped only after their checksum is verified. Failed runs are retried; corrupted/missing outputs are rebuilt.
- Retains previous file versions; outputs are written atomically. The SQLite audit records the latest status per source version/parser version, not every invocation.

Run one ingestion process at a time. A completed extraction is not proof that the financial figures, PDF columns, cached formulas, or geographic coverage are correct.

## VS Code setup on macOS

Clone the private repository using your GitHub account, then open the project folder in VS Code. Install the Microsoft Python extension and select the `.venv` interpreter.

```bash
git clone https://github.com/ItsYangCoder/ph-government-budget-analysis.git
cd ph-government-budget-analysis
git switch feature/ingestion-foundation
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e '.[dev]'
pytest -q
```

Python 3.11 or newer is supported. If your installed Python is not named `python3.12`, substitute its command. Git authentication is needed to clone this private repository.

Download the original Drive files locally. Preserve the six folders directly below `data/raw/`:

| Folder | Expected originals | Analytical purpose |
|---|---|---|
| `01_agency_actuals` | 2 `.xlsx` | AP1: actual agency financial measures |
| `02_approved_gaa` | 2 `.xlsx` | AP1: approved GAA appropriations |
| `03_sector_actuals` | 1 `.xlsx` | AP2: actual cash-based sector expenditure |
| `04_regional_actuals` | 2 `.pdf` | AP3: regional actual obligations |
| `05_population` | 1 `.xlsx` | AP3: projected mid-year population |
| `06_development_indicator` | 1 `.xlsx` | AP3: per-capita GRDP |

The ingestion manifest is reference metadata and is not counted as a government source dataset. Regional inputs must be the original PDFs, not the removed converted CSVs.

Run from the repository root:

```bash
pondolens --raw data/raw --output outputs
pondolens --raw data/raw --output outputs
```

First run: `EXTRACTED` for successful sources. Second unchanged run: nine `SKIPPED` messages. Errors exit nonzero; examine `outputs/latest_run.json`. The large GAA workbooks may take time and produce substantial structural output.

| Local output | Contents |
|---|---|
| `outputs/originals/` | Complete original files named by hash |
| `outputs/structure/` | JSONL structural extraction by source version |
| `outputs/audit.sqlite` | Source hashes, parser versions, counts, errors, output hashes |
| `outputs/latest_run.json` | Latest invocation summary; `ready_for_analysis` is false |

## Before analytical conversion

1. Map exact worksheet headers, financial measures, units, entity levels, and row hierarchy. Preserve department subtotals separately from agency detail.
2. Reconcile PDF regions against their actual column positions. Verify all figures, not only grand totals.
3. Check GAA and agency totals refer to the same entities and appropriation scope. Available appropriations are not automatically approved GAA.
4. Keep actual, program, and proposed values separate; use actual 2024–2025 sector columns.
5. For population, select regional total/both sexes/projected mid-year values rather than summing totals plus age/sex breakdowns.
6. Keep GRDP current prices, constant 2018 prices, growth rates, and indices separate.
7. Confirm geographic boundaries across all AP3 sources, including Negros Island Region and Sulu coverage. An unmatched boundary must block per-resident/GRDP comparisons rather than silently drop regions.
8. Keep Nationwide and Central Office for reconciliation, but exclude them from regional population denominators. Never sum subtotal and detail rows together.

Change `VERSION` in `src/pondolens/ingestion.py` when extraction rules change. This forces processing under a new version while retaining earlier outputs.

## Validation evidence

Automated tests use generated Excel/PDF fixtures and cover original preservation, rerun idempotency, revised-source retention, corrupt-output rebuilding, formulas/zero values, PDF text, retries, and input validation. These tests do not establish extraction accuracy for the nine government files. Full source reconciliation remains pending.
