# PondoLens — Bronze pipeline

Extract Philippine government budget and regional context sources faithfully, then load the outputs into Databricks Bronze. Current analysis scope is 2024–2025; other published years remain preserved where configured.

## Folder guide

| Folder | Purpose |
|---|---|
| configs/ | Source files, sheets, ranges, units, and validation rules |
| src/pondolens/ | Reusable Python extraction, hashing, state, and output writing |
| tests/ | Synthetic fixtures and automated tests |
| databricks/ | Notebook entry point and Delta loading helper |
| docs/ | Source notes and dated verification evidence |

Local data and outputs are excluded from Git.

## 1. Set up locally

From the repository folder, use Python 3.12:

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install '.[dev]'
python -m pytest -q
```

A normal installation is used because editable installation failed on the project Mac. After changing Python modules, reinstall with `python -m pip install --force-reinstall --no-deps .`.

## 2. Place original files

Keep originals unchanged under `data/incoming/`:

- `01_agency_actuals/`
- `02_sector_expenditure/`
- `03_regional_expenditure/`
- `04_population/`
- `05_development_indicators/`
- `06_geographic_reference/`

See each config's file patterns. Do not upload credentials or datasets to this repository.

## 3. Extract

Run these four source groups:

```bash
pondolens --config configs/population_economics.json --input-root data/incoming --output-root runtime --batch-id first-batch
pondolens --config configs/budget_sources.json --input-root data/incoming --output-root runtime --batch-id first-batch
pondolens --config configs/agency_details_grdp.json --input-root data/incoming --output-root runtime --batch-id first-batch
pondolens --config configs/psgc_reference.json --input-root data/incoming --output-root runtime --batch-id first-batch
```

Expected extraction units for the inspected files: 2 + 6 + 5 + 5 = 18. They produce 21 Parquet tables. These counts describe extraction units/tables, not agencies or original files.

## 4. Review outputs

Each `runtime/committed/<source_id>/<processing_key>/` contains:

- Parquet records with raw values, parsed numbers, source locations, and flags.
- `original.bin`: an exact binary copy of the original source.
- `metadata.json`: source headers and notes.
- `validation.json`: performed checks.
- `manifest.json`: checksums and counts.

`runtime/state.sqlite` tracks ingestion. `runtime/audit/` records runs. Preview CSVs are optional and are not the ingestion source.

Run the same extraction commands again: unchanged successful inputs should be SKIPPED. A processing key uses source ID, complete-file SHA-256, configuration hash, and extractor version. Batch ID does not create duplicates. Previous revisions remain retained.

For a new batch, place its originals in a separate incoming directory and change `--input-root` and `--batch-id`. Review/update config selectors, headers, periods, and controls when needed. Unsupported layouts require review; they are not automatically interpreted. Config filenames do not affect processing keys.

## 5. Load Databricks Bronze

Open `databricks/01_load_bronze.py` as a notebook. Upload committed directories, preserving their structure, to a Unity Catalog Volume. Set the three notebook widgets and run one explicit table first. Verify counts and rerun before loading the remaining tables.

The loader checks uploaded checksums and uses Delta MERGE on record IDs. Run one writer per target table. Local SQLite locking does not coordinate remote writers.

**Historical note:** earlier repository verification documentation predates the team's later Bronze workspace verification. See the Current Bronze status below for the latest team-reported load status.


## 6. Profile Bronze before Silver

Open `databricks/02_profile_bronze.py` after Bronze loading has been verified. The notebook is read-only: it inventories the current `pondolens.bronze` tables, checks record IDs and revisions, profiles raw values and quality flags, discovers JSON dimension keys before field-specific queries, and provides separate sections for MIA, RAZZ, ANJE, and JOY.

Do not treat a successful Bronze load as proof that sources are analytically comparable. In particular, do not sum every numeric cell, combine parent totals with children, or combine old and revised records without a documented selection rule. Raw-cell financial completeness and business-key checks remain pending until row/column mappings are verified.

Team assignments, the findings template, and the Silver-readiness checklist are in [docs/bronze_profiling_handoff.md](docs/bronze_profiling_handoff.md).

### Current Bronze status

The team reports that Databricks Bronze loading has been verified for 18 extraction packages producing 21 Delta tables and 798,440 records. Source Parquet and loaded Delta record counts matched, and an identical rerun produced zero candidate new rows. These are loading-fidelity checks only; the profiling notebook queries have not yet been executed and no profiling findings are claimed here.

## Scope and limitations

- Agency details/SUCs, total GRDP, and PSGC use raw-cell extraction, including blanks inside selected ranges. They are not cleaned financial/geographic models.
- Population and per-capita GRDP select configured 2024–2025 measures; this is not extraction of every published year.
- Preserve the 2025 SUC conflicting year headers and PSGC provincial-summary date conflict.
- Regional 2024 is actual obligations; regional 2025 is updated GAA. Do not equate them.
- Sector amounts are million PHP; regional amounts are thousand PHP. Program/proposed values remain separately labeled.
- 2026 PSGC is a dated reference, not proof of historical boundaries.
- No Silver cleaning, geographic joins, Gold models, dbt, or orchestration are implemented here.

Latest evidence: [docs/verification_status.md](docs/verification_status.md). Initial implementation snapshot: [docs/history/initial_execution_report.md](docs/history/initial_execution_report.md).
