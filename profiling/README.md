# Data profiling

One folder per dataset, with one executable SQL file, one data dictionary, and one findings record. Dataset owners remain responsible for source interpretation. Profiling reads persistent tables and may create session-only temporary views; it never writes Bronze, Silver, or the shared crosswalk.

## Dataset index

| Dataset / table suffix | Owner | Scope | Files |
|---|---|---|---|
| agency_actuals | Mia Barroga | Reference only | [SQL](bronze/agency_actuals/profiling.sql) · [Dictionary](bronze/agency_actuals/data_dictionary.md) · [Findings](bronze/agency_actuals/findings.md) |
| completion_rate | Rhea Alum | Active | [SQL](bronze/completion_rate/profiling.sql) · [Dictionary](bronze/completion_rate/data_dictionary.md) · [Findings](bronze/completion_rate/findings.md) |
| grdp_per_capita | Anjelika Marquez | Active | [SQL](bronze/grdp_per_capita/profiling.sql) · [Dictionary](bronze/grdp_per_capita/data_dictionary.md) · [Findings](bronze/grdp_per_capita/findings.md) |
| hospital | Joy | Active | [SQL](bronze/hospital/profiling.sql) · [Dictionary](bronze/hospital/data_dictionary.md) · [Findings](bronze/hospital/findings.md) |
| population | Razzelle Boreros | Active | [SQL](bronze/population/profiling.sql) · [Dictionary](bronze/population/data_dictionary.md) · [Findings](bronze/population/findings.md) |
| poverty_incidence | Mia Barroga | Active | [SQL](bronze/poverty_incidence/profiling.sql) · [Dictionary](bronze/poverty_incidence/data_dictionary.md) · [Findings](bronze/poverty_incidence/findings.md) |
| regional_appropriation | Razzelle Boreros | Active | [SQL](bronze/regional_appropriation/profiling.sql) · [Dictionary](bronze/regional_appropriation/data_dictionary.md) · [Findings](bronze/regional_appropriation/findings.md) |
| region_boundaries | Rhea Alum | Active map reference | [SQL](bronze/region_boundaries/profiling.sql) · [Dictionary](bronze/region_boundaries/data_dictionary.md) · [Findings](bronze/region_boundaries/findings.md) |
| regional_obligations | Mia Barroga | Active | [SQL](bronze/regional_obligation/profiling.sql) · [Dictionary](bronze/regional_obligation/data_dictionary.md) · [Findings](bronze/regional_obligation/findings.md) |
| service_access | Joy | Reference only | [SQL](bronze/service_access/profiling.sql) · [Dictionary](bronze/service_access/data_dictionary.md) · [Findings](bronze/service_access/findings.md) |
| unemployment_rate | Anjelika Marquez | Active | [SQL](bronze/unemployment_rate/profiling.sql) · [Dictionary](bronze/unemployment_rate/data_dictionary.md) · [Findings](bronze/unemployment_rate/findings.md) |

All table suffixes above use `pondolens.dev_bronze`. The obligations folder retains its established singular name; its table is plural. `manifest.json` is the machine-readable registry. Reference-only datasets are retained for lookup, not reintroduced into Gold. GRDP totals, CHED graduates and sector expenditure have no current profiling package in this checkout; historical mentions are not completed coverage.

## Run in Databricks

1. Complete Bronze ingestion and keep the source snapshot stable while profiling. Record the relevant `_run_id` and `_dataset_hash` values.
2. Use a Databricks SQL warehouse with SELECT access to the Bronze tables, metadata, and shared crosswalk. Crosswalk-dependent checks also need `pondolens.dev_silver.shared_region_crosswalk`; run its setup first. No business Silver table is needed.
3. Run [overview.sql](bronze/overview.sql) for shared row counts, rescue payloads and lineage. All registered tables, including reference-only tables, must exist for this combined query. If one is unavailable, run available dataset packages separately and record the missing table; do not fabricate a passing overview.
4. Run the complete dataset `profiling.sql` in order in one SQL session. Temporary views do not survive session changes. Do not run a later query alone before its setup.
5. Save result exports in the team's restricted evidence location. Record warehouse/runtime, execution time in UTC, source run/hash, query section, output counts, and evidence location in `findings.md`. Do not commit credentials, signed URLs, or full source-row dumps.
6. Review results and source notes before approving Silver treatments. Do not use a successful SQL execution as proof of data acceptance.

The new shared overview and revised Hospital/Regional Obligations scripts have not been executed against Databricks in this change. Existing findings retain their original evidence boundaries. Repository checks validate structure and SQL syntax only.

## Standard checks and interpretation

| Area | Review |
|---|---|
| Structure and scope | Actual types, source files/revisions, coverage, units, one-row meaning |
| Completeness | NULL/blank values, source markers, rescue payloads, required lineage |
| Uniqueness | Source-aware candidate keys and post-mapping keys; no silent deduplication |
| Validity | Strict year/integer rules, parse failures, ranges and accepted categories |
| Consistency | Crosswalk alias/year matches, release status, compatible geography and units |
| Reconciliation | Expected components, duplicates, unresolved inputs, differences and source-supported tolerance |
| Lineage | Source file/page/row when available, ingestion run/hash and timestamps |

A query returning no rows is a pass only when it is an exception query and the source/eligible population was confirmed nonempty. Empty coverage is not a pass. Missing components, markers or unparsed values make reconciliation unassessed; SUM ignoring NULLs must not disguise incomplete totals. Rates, per-capita values, and statistical measures are not additive.

Zero remains zero. Preserve `..`, `...`, dashes, spreadsheet errors and footnotes distinctly. Marker meanings and conversion factors are dataset-specific. Appropriation reconciliation currently uses a documented project dash-as-zero assumption; this must not become a global rule. Confirm source notes before treating it as a publisher definition.

Crosswalk aliases can repeat when the canonical pair is identical. Detect conflicting distinct pairs for the applicable year and avoid row multiplication. Dataset-specific historical NIR exceptions require documented evidence; they do not authorize changing the shared crosswalk's validity years. Current boundary geometry does not establish historical boundary compatibility.

## Findings record

Keep observed results, proposed treatment, approved treatment and pending verification separate. For each rerun, append:

| Field | Record |
|---|---|
| Execution time / warehouse | UTC timestamp; warehouse/runtime |
| Source snapshot | Ingestion run IDs and dataset hashes |
| Query section / evidence | Section name and restricted result-export location |
| Observed result | Counts, exception count, eligible comparison count |
| Decision | Accepted / review / not assessed, with source-supported reason |
| Follow-up | Owner and unresolved action |

Preserve earlier observations as dated snapshots. Do not update historical counts merely because SQL changed.

## Local and CI checks

```bash
python -m pip install -r profiling/requirements-checks.txt
python scripts/check_profiling.py
python -m pytest -q tests/unit/test_profiling_checks.py
```

Checks enforce the registry, package files, local Markdown links, SQL parsing, permitted statement types and unique session view names. They do not connect to Databricks, validate live column existence, or certify source accuracy. Rerun the SQL in Databricks before scheduling it.
