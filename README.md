# PondoLens — Philippine Government Budget Analysis

Python pipeline for preserving, converting, validating and locally ingesting Philippine government budget and indicator data.

## Status

| Component | Status |
|---|---|
| Excel/PDF extraction and source-specific long-form conversion | Implemented |
| Source checks and local SQLite ingestion | Implemented |
| Reviewed cross-source mapping and joins | Pending |
| Silver/Gold analytical layers and Databricks deployment | Planned |

Current inputs are nine DBM/PSA files: seven Excel workbooks and two PDFs. Agency, GAA and regional budget files cover FY2024–FY2025; sector, population and GRDP sources retain their own published periods.

## Quick start — macOS / VS Code

Run from the repository root, where `pyproject.toml` is located. The pipeline is currently on `dev`.

```bash
git clone https://github.com/ItsYangCoder/ph-government-budget-analysis.git
cd ph-government-budget-analysis
git switch dev
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m pytest -q
```

Place the originals in the folders listed in [Setup and verification](docs/setup.md), then run:

```bash
pondolens-long --raw data/raw --output outputs
pondolens-long --raw data/raw --output outputs
```

The unchanged second run should print `REUSED conversion`. CSV checksums are verified and SQLite is rebuilt as a current snapshot; rows are not appended again.

## Outputs

- Source-specific long-form CSVs and conversion reports.
- `outputs/latest_long_form.json`: source status, checks and analysis readiness.
- `outputs/long_form.sqlite`: passing source partitions and filtered views.

The current nine-source conversion produces eighteen CSVs because some sources separate detail, controls and supporting measures. They are not eighteen original sources. PASS means the implemented conversion checks passed; cross-source comparability still requires review.

## Repository structure

| Path | Purpose |
|---|---|
| `src/pondolens/ingestion.py` | Original preservation and structural extraction |
| `src/pondolens/converters/` | Source-specific converters |
| `src/pondolens/long_form.py` | Validation, rerun controls and SQLite publication |
| `scripts/build_department_mapping.py` | Generate a department mapping review CSV |
| `tests/` | Automated pipeline tests |
| `docs/` | Setup, data contracts and validation evidence |
| `.github/workflows/ci.yml` | Automated test workflow |
| `data/raw/`, `outputs/` | Local inputs and generated artifacts; excluded from Git |

## Technical documentation

- [Setup and verification](docs/setup.md)
- [Data contracts and ingestion rules](docs/long_form.md)
- [Recorded source validation](docs/evidence/long_form_validation.md)
- [Recorded rerun evidence](docs/evidence/long_form_rerun.json)

Next: review department/agency identities, fund scope and geographic boundaries; build local Silver/Gold; then implement Databricks file landing and Delta tables. Deployment configuration is not yet implemented.
