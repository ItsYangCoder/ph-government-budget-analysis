# Bronze Ingestion

## Overview

Load prepared CSV and Excel files into `pondolens.dev_bronze` using Auto Loader.

- Budget coverage: 2024–2025; 2021–2023 will be added later.
- Population coverage: 2020–2035.
- GRDP and GRDP per capita coverage: 2023–2025.
- Compute: Databricks Serverless, environment version 6.
- Script: `databricks/scripts/bronze/01_bronze_ingestion.py`.

## Sources

Original Excel/PDF files are stored locally and in the [project Drive folder](https://drive.google.com/drive/folders/1Pn3YUL1PAJWpqTBmoxtjoB5vhxPk51AD).

Sources were converted locally in VS Code into tabular files before upload. Prepared files are in the [longform folder](https://drive.google.com/drive/folders/1L_kvzPjQE60GjUvthLuwxbC3xKevHsoB).

Source root: `/Volumes/pondolens/dev_bronze/government_budget/source/`

| Folder | Accepted filenames | Target table |
|---|---|---|
| `01_agency_actuals` | `01_agency_actuals_*.csv` | `agency_actuals` |
| `02_sector_expenditure` | `02_sector_expenditure_*.csv` | `sector_expenditure` |
| `03_regional_expenditure` | `03_regional_expenditure_gaa_*.csv` | `regional_expenditure_gaa` |
| `03_regional_expenditure` | `03_regional_expenditure_obligations_*.csv` | `regional_expenditure_obligations` |
| `04_population` | `*.csv` (currently `ph_population_projection.csv`) | `population` |
| `05_development_indicators` | `grdp_20*.xlsx` | `grdp` |
| `05_development_indicators` | `grdp_per_capita_20*.xlsx` | `grdp_per_capita` |

Population uses `ph_population_projection.csv`. GRDP uses `grdp_2023_2025.xlsx` and `grdp_per_capita_2023-2025.xlsx`. All target tables are under `pondolens.dev_bronze`.

## Loading

The script creates missing tables and appends new rows.

- CSV: headers become column names; source values remain strings for cleaning in Silver.
- Excel: reads the first sheet, with row 1 as the header; column types are inferred. Schema evolution is disabled.

Added metadata:

- `_source_file`: source file path.
- `_ingested_at`: loading timestamp.
- `_rescued_data`: unexpected CSV columns or parsing issues preserved for review.

Each dataset has its own checkpoint under the Volume’s `_ingestion` folder. Checkpoints track processed files so reruns do not reload them. The script processes available files, then stops.

## Run and Add Batches

1. Upload prepared files into the matching source folders.
2. Run the ingestion script with Volume and table access.
3. Check row counts and review CSV `_rescued_data`.

For new batches, follow the existing filename patterns and rerun. No year list needs updating. New Excel batches must keep the expected sheet layout and schema.

Keep checkpoints and loaded filenames unchanged. Renamed/copied files can load again, and duplicate rows within files are not removed. Previously loaded data corrections require a separate process.

## Verification

As of October 9, 2026, the original five tables retained their counts across four reruns. Both GRDP tables also retained 114 rows after rerunning ingestion.

| Table | Verified CSV data rows | Bronze rows |
|---|---:|---:|
| `agency_actuals` | 3,554 | 3,554 |
| `sector_expenditure` | 162 | 162 |
| `regional_expenditure_gaa` | 1,920 | 1,920 |
| `regional_expenditure_obligations` | 1,785 | 1,785 |
| `population` | 16,416 | 16,416 |
| `grdp` | 114 | 114 |
| `grdp_per_capita` | 114 | 114 |

CSV counts exclude headers and were checked against Drive files. Population was counted from the Drive longform file. Bronze counts and rerun results were supplied by the team.

Each GRDP table has 19 rows per year and price basis: 19 × 3 years × 2 price bases = 114 rows. Independent Excel source-row reconciliation remains pending.

The checked CSVs had no fully blank records, repeated headers, or inconsistent column counts. Duplicate checks, missing values, units, region matching, and value-level reconciliation remain part of profiling.