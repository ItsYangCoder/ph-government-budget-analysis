# PondoLens engineering handoff

PondoLens prepares Philippine government budget and expenditure reports for reproducible analysis. We preserve the original files, convert each source according to its own layout, validate the resulting tables, and publish passing sources to a local SQLite database. Development happens in VS Code; reviewed Silver and Gold logic will be developed locally before final Databricks integration.

The current executable deliverable is **source conversion and local ingestion**. It is not yet a complete Silver, Gold, or deployed Databricks pipeline. This guide lets another engineer identify what exists, run it, inspect the evidence, and continue the remaining work.

Documentation date: **1 October 2026, Asia/Manila**. Code baseline inspected: `dev` at `8cca67b39cfe88be7b79c92cebc6dc1d7b09d2e0`. Evidence refers to the exact source hashes in [the verification record](evidence/long_form_validation.md), not future source revisions.

## Read this first

| Need | Document |
|---|---|
| Understand current state, tools, ownership and organization | This engineering handoff |
| Set up, execute, verify and recover the local pipeline | [Local runbook](local_runbook.md) |
| Understand the nine sources, eighteen CSVs, grain and lineage | [Source contracts](source_contracts.md) |
| Follow the planned Silver, Gold and Databricks integration | [Pipeline architecture](pipeline_architecture.md) |
| Inspect current schema rules, tolerances and SQL views | [Long-form specification](long_form.md) |
| Inspect recorded real-source validation and rerun results | [Validation evidence](evidence/long_form_validation.md) and [rerun evidence](evidence/long_form_rerun.json) |

The organization follows the handoff concerns in the [FTW B12 repository review](https://ogbinar.com/ftw-b12-repository-review/): purpose, architecture, model, reproducible execution, quality, decisions, organization and collaboration. This is project documentation, not an independent score or a claim of production readiness.

## Purpose and analytical scope

The reports use different layouts, reporting levels, units and financial bases. A direct union or a name-only join could double-count totals, associate the wrong region with an amount, or compare approved appropriations with a different funding scope.

The intended users are the capstone team, reviewers, and engineers extending the pipeline. The intended analytical outputs are department budget allocation and changes, approved-budget versus actuals comparisons where scope is verified, and separate sector or regional spending analysis. Population and per-capita GRDP provide context only where years and geographic boundaries can be aligned.

The current source contract has nine files across six folders. Paired GAA, agency actuals and regional reports cover FY2024 and FY2025. Sector, population and GRDP workbooks contain their own series and measures; not every observation is a FY2024 or FY2025 actual. Five-year completeness is not established by this ingestion run.

## Implementation status

| Capability | Status | Evidence or completion condition |
|---|---|---|
| Original preservation and structural extraction | Implemented | `pondolens`, source hashes, structural JSONL and audit database |
| Source-specific long-form conversion | Implemented | `pondolens-long`, Excel and regional converters |
| Source validation and SQLite publication | Implemented | Nine passing sources; current snapshot in `outputs/long_form.sqlite` |
| Unchanged conversion reuse and snapshot repair | Implemented | Fingerprint/checksum checks and SQLite transaction; recorded rerun evidence |
| Department mapping candidate generation | Implemented | `scripts/build_department_mapping.py` on `dev` |
| Human source and mapping review | Pending completion | GitHub issues #2–#6; reviewed findings and CSV required |
| Apply approved mappings and publish Silver | Planned | Mapping uniqueness, coverage, join cardinality and reconciliation gates |
| Gold dimensions, facts and analytical marts | Planned | Approved business questions, table grains and passing model checks |
| Export package and Databricks Delta ingestion | Planned | Explicit schemas, transfer manifest and local/remote parity checks |
| Scheduled Databricks jobs and deployment | Planned | Reviewed configuration, access, failure handling and remote run evidence |
| Dashboard | Planned | Validated Gold tables and agreed metric definitions |

`PASS` means a source passed the implemented conversion controls. It does not approve cross-source financial comparability or every possible source-data error. `ready_for_cross_source_analysis` remains false in the current converter. Completing a review CSV will not change that flag automatically.

## Recorded results

The saved verification record reports **1,489,811 long rows**, **9/9 sources passing**, **55,393 reconciliation checks passing**, and **zero duplicate keys at the implemented grains**. All 23,707,516 extracted nonempty Excel cells were compared with the originals with zero mismatches; four PDF pages matched original text and page counts. These structural checks do not replace review of the meaning of extracted financial rows.

The team terminal run also showed **19 tests passing** and an unchanged second long-form run printing `REUSED conversion`. The saved full-source rerun record compares database counts and ordered values, not only the console message. Totals include candidates and control rows; they are not counts of analysis-ready facts.

Do not run `SUM(value)` over all retained tables. Select a documented reporting level, unit, status, financial basis and funding scope. Budget control totals, department totals, agency breakdowns, growth rates and per-capita indicators have different purposes.

## Tools and execution responsibilities

| Tool | Current or planned | Responsibility |
|---|---|---|
| VS Code and Microsoft Python extension | Current | Edit code and select the local `.venv` interpreter |
| Python 3.12 and virtual environment | Current | Run the CLI and tests; package supports Python 3.11+ |
| `openpyxl` | Current dependency | Read Excel values, formulas, cached values and formatting metadata |
| `pdfplumber` | Current dependency | Read PDF text and word coordinates for regional alignment |
| Python `csv`, `decimal`, `hashlib`, `json`, `sqlite3` | Current standard library | CSV, exact numeric parsing, hashes, metadata and SQLite publication |
| `pytest` | Current development dependency | Regression and publication/recovery tests |
| Git and GitHub | Current | Version code and docs; issues, PRs and team Kanban |
| GitHub Actions | Current CI | Install the package and run `pytest` on pushes and PRs; no deployment yet |
| PyArrow | Planned local dependency | Typed Parquet export after explicit schema and decimal precision are approved |
| Databricks CLI and deployment bundles | Planned | Validate and deploy environment-specific job definitions |
| Unity Catalog Volumes | Planned Databricks storage | Land source/export files and transfer manifests |
| Spark SQL / PySpark and Delta tables | Planned Databricks compute/storage | Typed ingestion, Silver/Gold execution and validation |
| Databricks Jobs and SQL Warehouse | Planned | Orchestration and SQL/dashboard consumption |

SQLite is the current database; DuckDB, Pandas, dbt, Great Expectations, Auto Loader and cloud buckets are not required by the present package. Introduce another tool only for a defined need and document its installation, role and tests. The current batch of nine sources does not require streaming ingestion.

## Current repository structure

Paths below describe the inspected `dev` branch plus this documentation change. The local runtime directories are excluded from Git.

```text
ph-government-budget-analysis/
  README.md
  pyproject.toml
  .gitignore
  .github/workflows/ci.yml
  src/pondolens/
    __init__.py
    ingestion.py
    long_form.py
    converters/
      __init__.py
      common.py
      excel.py
      regional.py
  scripts/build_department_mapping.py
  tests/
    test_ingestion.py
    test_long_form.py
  docs/
    pipeline_handoff.md
    local_runbook.md
    source_contracts.md
    pipeline_architecture.md
    long_form.md
    evidence/
      long_form_validation.md
      long_form_rerun.json
  data/raw/                     # local original source files
  outputs/                      # local generated artifacts
  .venv/                        # local interpreter and packages
```

`src/` contains reusable processing code. `scripts/` contains operator utilities. `tests/` contains executable regression checks. `docs/` contains behavior, operations and design documentation. Generated CSVs, databases, structural archives and review outputs do not belong in source control.

## Proposed extension structure

**All paths in this block are planned additions, not available commands or implemented modules.** Keep the existing package and CLI; do not create a second competing pipeline.

```text
config/
  local.example.yml
  databricks.example.yml
  source_contracts.yml
src/pondolens/
  mappings/department.py
  mappings/geography.py
  silver/agency.py
  silver/sector.py
  silver/regional.py
  silver/context.py
  gold/dimensions.py
  gold/facts.py
  gold/marts.py
  quality/contracts.py
  quality/reconciliation.py
  quality/run_audit.py
  export/parquet.py
  databricks/load_delta.py
  databricks/validate_parity.py
scripts/
  run_local_pipeline.py
  export_release.py
resources/pondolens_job.yml
databricks.yml
tests/unit/
tests/integration/
tests/fixtures/
docs/decisions/
```

Proposed generated locations under ignored `outputs/`: `silver/<run_id>/`, `gold/<run_id>/`, `releases/<release_id>/`, and `quarantine/<run_id>/`. Reviewed and approved mapping versions should have controlled storage and checksums. A sanitized, non-sensitive approved lookup may be versioned under a future `reference/` directory after review; the current generated review CSV stays outside Git.

Configuration should name source roots, output roots, approved mapping versions, target catalogs/schemas, release IDs and financial scope. Keep credentials in the platform authentication mechanism, not in YAML or notebooks. Do not invent current config files: the executable CLI currently exposes `--raw`, `--output`, the structural ZIP option and GAA unit/evidence options.

## Review ownership and collaboration

[Team Kanban](https://github.com/users/ItsYangCoder/projects/7) is the shared review tracker. At board setup the five tasks were in Ready; reviewers update the live status as work progresses.

| Owner | Review task | GitHub account |
|---|---|---|
| Razz | [GAA source review #2](https://github.com/ItsYangCoder/ph-government-budget-analysis/issues/2) | `razzelleb` |
| Anji | [Agency actuals review #3](https://github.com/ItsYangCoder/ph-government-budget-analysis/issues/3) | `anjelikamarquez` |
| Mia | [Regional and population review #4](https://github.com/ItsYangCoder/ph-government-budget-analysis/issues/4) | `miabarroga-de` |
| Joy | [Sector and GRDP review #5](https://github.com/ItsYangCoder/ph-government-budget-analysis/issues/5) | `JoyInBytes` |
| Razz and Anji | [Department mapping review #6](https://github.com/ItsYangCoder/ph-government-budget-analysis/issues/6) | Both accounts |

Rhea maintains the ingestion implementation and integrates verified findings. She is not assigned manual original-source review in this allocation. Findings should identify the source sheet/cell or PDF page/row, expected value, converted value and review decision. Correct the converter and rerun it rather than manually editing generated financial CSVs.

Use a task branch from `dev`, focused commits and a PR into `dev`. Include problem, resulting behavior, source evidence and validation. Promote to `main` only after the agreed release gates pass. Commit counts are not proof of review quality; link the issue, changed logic and actual test evidence.

## Engineering decisions and remaining limits

We use one ingestion entry point with source-specific converters because layout and semantics vary. Once converted, tables share an explicit schema and can be loaded together while preserving their dataset identity. A common schema does not make all measures safe to union or sum.

We retain candidates and source errors rather than silently dropping them. The 127 original agency rate errors remain identifiable as undefined rates. Controls are separate from financial detail so totals can check the conversion without becoming another contribution to expenditure.

We use Decimal for financial reconciliation and retain source values as text in SQLite. Numeric types for Silver, Parquet and Delta require documented precision/scale and overflow checks; automatic inference is insufficient for leading-zero codes and mixed units.

Local single-process execution is deliberate for the current source set. It provides a reproducible development path without workspace dependencies. SQLite transactions and a local lock do not provide distributed orchestration or Delta merge behavior. Databricks integration requires an adapter, configuration and fresh validation.

Large structural JSONL is an optional audit artifact. Direct-original mode does not require recreating or uploading its multi-gigabyte archive. Keep originals, approved release files and small reports/manifests; remove redundant structural copies only after backup and review retention are confirmed. JSON file size and purpose matter: a small manifest is not the same artifact as an 8+ GB structural extraction.

The unresolved analytical risks are department identity, fund coverage, actuals detail hierarchy, geographic boundaries including NIR/Sulu, and different financial bases. Gold must not claim approved-budget utilization or spending per resident until the relevant gates in [the architecture plan](pipeline_architecture.md) are satisfied.
