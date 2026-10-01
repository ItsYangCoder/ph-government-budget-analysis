# Local setup and operations

This is the executable run path for the implemented source pipeline. Run commands from the repository root containing `pyproject.toml`. Silver, Gold and Databricks commands are not implemented yet; their design is documented separately.

## Prerequisites and access

Use Git, VS Code with the Microsoft Python extension, and Python 3.12. Python 3.11+ is supported by package metadata; recorded tests used Python 3.12. Obtain access to the repository and the team-shared originals. Source files are not included in Git, so cloning alone cannot reproduce the real-source run.

For a new checkout on macOS:

```bash
git clone https://github.com/ItsYangCoder/ph-government-budget-analysis.git
cd ph-government-budget-analysis
git switch dev
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m pytest -q
pondolens-long --help
```

For an existing clean checkout:

```bash
cd /Users/rheaalum/ph-government-budget-analysis
git status -sb
git fetch origin
git switch dev
git pull --ff-only
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m pytest -q
```

The `/Users/rheaalum/...` path is Rhea's local example; another engineer must use their own checkout path. Save or commit local edits before switching/pulling. Select `.venv/bin/python` in VS Code. Expected current test result: `19 passed`; runtime duration can differ. The dependency ranges in `pyproject.toml` are not a lockfile. Capture installed versions for each run when comparing environments.

## Provision originals

Create `data/raw/` and copy the six source folders into it. Retain the original workbook/PDF contents. Keep expected inputs directly inside each numbered folder, not inside another nested copy of the package.

```bash
mkdir -p data/raw
open data/raw
```

The Finder command is macOS-specific. The source contract expects **7 Excel workbooks and 2 PDFs**, with folder counts **2, 2, 1, 2, 1, 1**. The original regional PDFs are the inputs; the earlier manually converted PDF CSVs are not inputs. A download manifest is not one of the nine source files.

Check the input inventory before conversion:

```bash
python - <<'PY'
from pathlib import Path
from pondolens.ingestion import discover

root = Path('data/raw').resolve()
files = discover(root)
for path in files:
    print(path.relative_to(root))
print('Expected source files:', len(files))
PY
```

Discovery checks folder-specific extension/count rules. The long-form run also checks the distinct FY2024/FY2025 source pairs. Unknown future files/layouts require updated source contracts and tests; this pipeline is not a generic PDF or Excel converter.

## Run the current pipeline

The recommended path reads originals directly:

```bash
pondolens-long --raw data/raw --output outputs
```

Expected successful behavior: nine `PASS` sources, a saved report, and publication to `outputs/long_form.sqlite`. For the verified source versions the total is **1,489,811 rows across 18 CSVs**, including controls and candidates. The first run can take time because the GAA workbooks are large. Wait for the final report and exit status; partial `PASS` messages do not establish completion.

Optional structural preservation, if needed for audit:

```bash
pondolens --raw data/raw --output outputs
```

This produces preserved originals, structural JSONL and `audit.sqlite`. It is a different operation from long-form conversion and is not a prerequisite for direct-original mode. For an existing complete structural archive, the supported alternative is:

```bash
pondolens-long --structure-zip /absolute/path/pondolens-extraction.zip --output outputs
```

Choose one input mode for a comparison. Original and ZIP modes have different fingerprints. ZIP mode streams structural records without unpacking all JSONL to disk; it does not independently recalculate original formulas.

## Verify publication and rerun behavior

Inspect the report and capture a database digest. The following uses read-only SQLite access and hashes every stored field in deterministic key order for each published dataset. It does not sum incompatible measures.

```bash
python - <<'PY'
import hashlib
import json
import sqlite3
from pathlib import Path
from pondolens.long_form import DATASETS

report = json.loads(Path('outputs/latest_long_form.json').read_text())
print('run_id:', report['run_id'])
print('reused_conversion:', report['reused_conversion'])
print('ready_for_source_tables:', report['ready_for_source_tables'])
print('ready_for_cross_source_analysis:', report['ready_for_cross_source_analysis'])
for source in report['sources']:
    print(source['source'], source['status'], sum(source['counts'].values()))

path = Path('outputs/long_form.sqlite').resolve()
with sqlite3.connect(path.as_uri() + '?mode=ro', uri=True) as db:
    for table in DATASETS:
        digest = hashlib.sha256()
        count = 0
        for row in db.execute(f'SELECT * FROM "{table}" ORDER BY source, record_key'):
            digest.update(json.dumps(row, ensure_ascii=False,
                                     separators=(',', ':')).encode('utf-8'))
            digest.update(b'\n')
            count += 1
        print(table, count, digest.hexdigest())
PY
```

Save the output, run the unchanged command again, and repeat the verification:

```bash
pondolens-long --raw data/raw --output outputs
```

Expected: `REUSED conversion`, unchanged run ID, identical per-table counts and digests, and cross-source readiness still false. SQLite is rebuilt even on reuse, so missing database rows can be repaired. A reuse message alone is not a full duplicate or value-stability test.

The source fingerprints and CSV/report checksums are in the generation manifest. Reuse requires these recorded outputs to remain intact. Source, code, configuration or relevant dependency changes cause a new conversion fingerprint. Generated files should be read, not edited to fix a source discrepancy.

## Review file generation

After successful local ingestion:

```bash
python scripts/build_department_mapping.py
```

Expected output for the reviewed source set: `outputs/department_mapping_review.csv`, with 74 department/fund entries. The script proposes normalized name candidates; it does not approve matches or apply mappings. It refuses to overwrite an existing review file to preserve human edits.

Razz checks GAA names/codes and Anji checks agency actuals names/scope. They use one shared reviewed copy and record original sheet/cell references. Unmatched and ambiguous entries stay pending. Preserve identifiers as text when opening the CSV in a spreadsheet.

The approved mapping application and its downstream execution commands are planned work. Do not interpret a completed CSV review as an automatically mapped database.

## Failure handling

| Symptom | Meaning and operator action |
|---|---|
| `pondolens-long: command not found` | Confirm the project root and active interpreter; reinstall with `python -m pip install -e '.[dev]'`. `python -m pondolens.long_form --raw data/raw --output outputs` is also supported. |
| Unexpected source count or duplicate year | Remove accidental copies from the input folder or supply the correct originals; do not delete genuine source rows to force PASS. |
| `REVIEW_REQUIRED`, exit code 2 | Conversion completed but one or more source gates failed. Inspect blockers and retained CSVs. A blocked source is unavailable in the current database snapshot. |
| Exit code 1 | Command failure. Inspect the exception and fix input, filesystem or runtime issues before retrying. |
| Header/footer warning from `openpyxl` | For the verified files it concerns formatting; original bytes are preserved. Check final source status and evidence rather than suppressing validation. |
| Lock file exists | Confirm no ingestion process is active. Remove a stale `outputs/.long_form.lock` only after confirming the owning process stopped. |
| Modified or corrupted CSV/manifest | Rerun from intact originals. Checksum validation prevents reuse and rebuilds conversion. |
| Publication failure | SQLite transaction rolls back. Keep prior artifacts; fix the cause and rerun, then verify the current snapshot. |
| Unknown/revised GAA unit | Publication requires verified unit evidence. Never guess a scale or reuse evidence tied to another source hash. |

Only run one local long-form process at a time. Ensure sufficient disk capacity for originals, CSV generations, SQLite and any optional structural archive. No benchmarked minimum disk or conversion duration is claimed.

## Retention and handoff

Keep original source files, final reviewed mappings, approved releases and the small report/manifest JSON files. Previous generation folders are retained for audit, so physical files can accumulate across changed runs without duplicate rows in the current SQLite snapshot.

The structural JSONL archive can be multi-gigabyte. Direct-original conversion does not depend on it. Remove redundant structural copies only after confirming originals and required audit evidence are backed up and the team review is complete. Do not delete all JSON files by extension.

A handoff is complete for this local phase when another engineer can provision the exact sources, install the package, run all nine sources, reproduce the unchanged rerun, inspect the documented grains and identify every remaining review gate.
