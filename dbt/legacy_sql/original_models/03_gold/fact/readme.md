# PondoLens Gold Fact Tables

Author: Christine Joy D. Balansay  
Updated: 2026-10-21  
Platform: Databricks SQL / Delta Lake

## Overview

| Table | Purpose | Business grain |
| --- | --- | --- |
| `pondolens.dev_gold.fact_regional_indicator` | Regional development measurements | Location × year × indicator definition |
| `pondolens.dev_gold.fact_regional_expenditure` | Appropriations and obligations in PHP | Location × year × particular |

Both tables use `CREATE TABLE IF NOT EXISTS` and `MERGE`. Temporary views prepare records; final outputs are persistent Delta tables.

This README describes the scripts and development results supplied by the author. Snapshot counts are verification evidence, not permanent row-count requirements for future source updates.

## Dependencies and execution order

1. Load and validate the Silver sources.
2. Load and validate the required dimensions.
3. Run each fact loader in order within one SQL session.
4. Review assertions, MERGE metrics, financial reconciliation, and coverage before releasing analytics.

| Dimension | Key | Used by |
| --- | --- | --- |
| `pondolens.dev_gold.dim_location` | `location_id` | Both facts |
| `pondolens.dev_gold.dim_year` | `year_id` | Both facts |
| `pondolens.dev_gold.dim_indicator` | `indicator_id` | Indicator fact |
| `pondolens.dev_gold.dim_particular` | `particular_id` | Expenditure fact |

`dim_particular` is a persistent Delta table with a fixed canonical registry. Its active seed contains 51 definitions, including UNKNOWN at 30000. ID 30051 is retired and must not be reused. A retained legacy dimension row may still exist physically; zero expenditure fact references to that ID were verified. The loader does not remove the dimension row.

## fact_regional_indicator

### Schema

| Column | SQL type | Nullable | Description |
| --- | --- | --- | --- |
| `fact_indicator_id` | BIGINT | No | Fact identifier; initial allocation starts at 50001 |
| `location_id` | INT | No | Location dimension key |
| `year_id` | INT | No | Year dimension key |
| `indicator_id` | INT | No | Indicator definition key |
| `measurement` | DECIMAL(28,10) | Yes | Observed value in the dimension-defined unit |
| `value_status` | STRING | No | Availability or preserved source marker |
| `source_table` | STRING | No | Originating Silver table |
| `processed_at` | TIMESTAMP | No | Insertion or latest changed-record timestamp |

Business key: `(location_id, year_id, indicator_id)`.

### Sources and definition mapping

Sources are under `pondolens.dev_silver`.

| Source | Indicator IDs | Definitions |
| --- | --- | --- |
| `unemployment_rate` | 40001 | Unemployment rate |
| `grdp_per_capita` | 40002–40003 | Current-price and constant-2018-price GRDP per capita |
| `hospital` | 40004 | Government hospital count |
| `poverty_incidence` | 40005–40006, 40016 | Family/population incidence and annual per-capita threshold |
| `completion_rate` | 40007–40015 | Three education levels × three sex groups |
| `service_access` | 40017–40019 | Drinking-water, sanitation, and handwashing access |

Scope: regional observations in 2021–2025, subject to source availability. National and Central Office observations are excluded. Use `dim_indicator` for exact definition names and units.

### Transformation rules

- Standardize region codes before dimension lookup.
- Map GRDP `price_basis = 2018` to constant 2018 prices and `price_basis = year` to current prices.
- Keep family and population poverty incidence separate.
- Validate agreement of repeated poverty thresholds, then load one threshold per region/year; never sum repeated thresholds.
- Normalize education unit `percent` to `%` and preserve missing source markers.
- Preserve handwashing's denominator `% of consenting families`; water and sanitation use `% of families`.
- Include the 102 regional PSA APIS observations for 2022 and 2024.

| `value_status` | Treatment |
| --- | --- |
| `available` | Numeric measurement required |
| `source_marker_two_dots` | NULL measurement |
| `source_marker_three_dots` | NULL measurement |

Markers are not converted to zero. Their interpretation remains subject to the original source methodology.

### Recorded development results

| Metric | Result |
| --- | ---: |
| Rows / unique fact IDs | 1,409 / 1,409 |
| Distinct indicator definitions | 19 |
| ID range | 50001–51409 |
| NULL measurements | 189 |

The 189 NULLs consist of 27 education observations with two-dot markers across 2021–2023 and 162 observations with three-dot markers in 2025. Detailed unchanged-rerun MERGE metrics for this fact were not supplied in the recorded evidence.

## fact_regional_expenditure

### Schema

| Column | SQL type | Nullable | Description |
| --- | --- | --- | --- |
| `regional_expenditure_id` | BIGINT | No | Fact identifier; initial allocation starts at 60001 |
| `year_id` | INT | No | Year dimension key |
| `location_id` | INT | No | Location dimension key |
| `particular_id` | INT | No | Canonical agency/fund dimension key |
| `appropriation_amount` | DECIMAL(20,4) | Yes | Appropriation in PHP |
| `appropriation_value_status` | STRING | No | Availability/source status |
| `obligation_amount` | DECIMAL(20,4) | Yes | Reported obligation in PHP |
| `obligation_value_status` | STRING | No | Availability/source status |
| `processed_at` | TIMESTAMP | No | Insertion or latest changed-record timestamp |

Business key: `(year_id, location_id, particular_id)`.

### Sources, units, and geographic scope

| Source | Amount column |
| --- | --- |
| `pondolens.dev_silver.regional_appropriations` | `appropriation_amount` |
| `pondolens.dev_silver.regional_obligations` | `expenditure_amount` |

Scope: 2021–2025, including regional, Nationwide, and Central Office records. Regional analytics must filter `dim_location.geographic_level = 'region'`.

Gold treats Silver amounts as PHP without another multiplier. Bronze appropriations use `thousand pesos` in all inspected years. The sampled CSC–BARMM 2021 record reconciled from 39,184 in Bronze to 39,184,000 in Silver. This sample does not independently verify every source conversion.

### Canonical agency mapping

Whitespace and case are normalized before applying these aliases:

| Source label | Canonical label |
| --- | --- |
| THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE | PRESIDENTIAL COMMUNICATIONS OFFICE (PCO) |
| PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE | PRESIDENTIAL COMMUNICATIONS OFFICE (PCO) |
| OFFICE OF THE PRESS SECRETARY | PRESIDENTIAL COMMUNICATIONS OFFICE (PCO) |
| DEBT SERVICE FUND-INTEREST PAYMENT | DEBT INTEREST PAYMENTS |

**Press Secretary and PCO use the same canonical ID, 30033.** EO No. 11, dated December 29, 2022, renamed the Office of the Press Secretary as the Presidential Communications Office. See the [Supreme Court E-Library text of EO No. 11](https://elibrary.judiciary.gov.ph/thebookshelf/showdocs/5/96173).

Original source labels remain in Silver. Canonical agency identity does not, by itself, establish identical appropriation/obligation budget coverage.

### Combining sources and handling missingness

A FULL OUTER JOIN uses `year × region_code × category × canonical particular`. Each source observation must survive once. Unmatched counterparts remain explicit rather than being filled with zero.

| Status | Applies to | Amount treatment |
| --- | --- | --- |
| `REPORTED` | Both | Positive numeric amount |
| `REPORTED_ZERO` | Both | Explicit numeric zero |
| `SOURCE_NULL` | Appropriations | NULL from Silver |
| `SOURCE_DASH` | Obligations | NULL; source dash preserved through status |
| `SOURCE_BLANK` | Obligations | NULL; source blank preserved through status |
| `NOT_IN_SOURCE` | Both | NULL; matching source observation absent |

Silver obligation dash/blank placeholders are stored as zero. Gold represents them as NULL with explicit status; the loader does not modify Silver. Numeric zero in appropriations is retained as supplied by Silver; classification as `REPORTED_ZERO` is not independent proof of how the original document displayed that value.

### PCO consolidation and guarded legacy cleanup

The initial separation produced 4,411 fact rows. After verification, 19 Press Secretary appropriation records were consolidated with their matching 2023 PCO records.

- Existing PCO fact IDs were preserved.
- The 19 superseded fact rows at retired ID 30051 were removed.
- PCO obligations were preserved and total financial amounts remained unchanged.
- The maintained loader includes the alias, so regular reruns do not recreate separate rows.

The current revised loader uses `fre_merge_actions` with `UPSERT` and guarded `DELETE_LEGACY` actions. Before any legacy deletion, it checks that there are zero or 19 affected rows, that they belong to 2023, that appropriation amounts/statuses match the canonical source, and that no obligation values would be discarded.

Legacy rows are backed up in `pondolens.dev_gold.fact_expenditure_legacy_30051_backup` before deletion; the loader requires exact backup coverage of any rows it will remove. Existing backups are not overwritten. A mismatched backup stops the load for investigation. After cleanup, the legacy branch is a no-op.

The upsert and legacy deletion occur in one Delta MERGE. General source omissions are not automatically deleted: unexpected nonlegacy target keys absent from the canonical source trigger validation failure.

### Recorded results after consolidation

| Metric | Result |
| --- | ---: |
| Rows / unique fact IDs | 4,392 / 4,392 |
| Remaining 30051 fact references | 0 |
| Appropriation source records | 4,256 |
| Obligation source records | 3,822 |
| Total appropriation PHP | 26,891,524,300,000 |
| Total reported obligation PHP | 27,914,380,625,000 |
| 2023 PCO rows / populated appropriations | 19 / 19 |
| 2023 PCO appropriation PHP | 1,130,587,000 |
| 2023 PCO obligation PHP | 1,598,561,000 |

Totals describe stored geographic coverage. They must not be presented as independently reconciled national totals without checking source coverage and overlap.

Latest unchanged-rerun MERGE evidence: **0 affected, 0 updated, 0 deleted, 0 inserted**. A separate timestamp-diff test was not supplied; the loader preserves timestamps for unchanged rows.

### Recorded status distribution

| Appropriation status | Obligation status | Rows |
| --- | --- | ---: |
| NOT_IN_SOURCE | REPORTED | 33 |
| NOT_IN_SOURCE | SOURCE_BLANK | 56 |
| NOT_IN_SOURCE | SOURCE_DASH | 47 |
| REPORTED | NOT_IN_SOURCE | 30 |
| REPORTED | REPORTED | 2,411 |
| REPORTED | SOURCE_DASH | 107 |
| REPORTED_ZERO | NOT_IN_SOURCE | 450 |
| REPORTED_ZERO | REPORTED | 45 |
| REPORTED_ZERO | SOURCE_DASH | 1,087 |
| SOURCE_NULL | NOT_IN_SOURCE | 90 |
| SOURCE_NULL | SOURCE_DASH | 36 |
| **Total** | | **4,392** |

## Operating the loaders

- Use one writer per fact loader. Pause competing loads during migration or repair.
- Keep sources and dimensions stable during a run: temporary views are not frozen snapshots.
- Run all statements in the same session; do not run a mapping view alone and expect stored facts to change.
- Save the approved alias in the actual maintained loader. Running an old script can recreate incorrect records.
- Stop on any error. `ASSERT_TRUE` returns NULL on success.
- `CREATE TABLE IF NOT EXISTS` does not migrate incompatible schemas or replace materialized views.
- Do not include old standalone PCO migrations in recurring jobs.

Both loaders use insert/update MERGE behavior, stable business-key matching, and new-ID allocation only for previously unseen keys. `processed_at` changes on insertion or changed measurements/statuses.

The complete revised expenditure script has 36 statements. If executed unchanged with one result per statement, these review positions apply:

| Result | Content |
| ---: | --- |
| 28 | MERGE metrics |
| 33 | Overall fact summary |
| 34 | Consolidated 2023 PCO |
| 35 | Year/geographic coverage |
| 36 | Status distribution |

Interfaces may group results differently. Identify MERGE metrics by `num_affected_rows`, `num_updated_rows`, `num_deleted_rows`, and `num_inserted_rows` when numbering differs.

## Validation contract

- No duplicate source business keys after name normalization.
- Unique dimension IDs and lookup keys.
- No missing required foreign keys or multiplied joins.
- No UNKNOWN or retired 30051 mappings in the normalized expenditure source.
- Unique fact IDs and fact business keys.
- Saved measurements/amounts/statuses match normalized Silver observations.
- Expenditure totals and populated-value counts reconcile to the normalized Silver sources.
- Unexpected nonlegacy source omissions stop the expenditure load.

NOT NULL columns are declared. Uniqueness and foreign-key validity are checked by the pipelines; these tables do not declare database-enforced unique or foreign-key constraints.

Assertions, backup creation, DDL, and MERGE are separate statements. A failed post-load assertion does not roll back an already committed MERGE.

## Standalone checks

```sql
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT regional_expenditure_id) AS unique_fact_ids,
    COUNT_IF(particular_id = 30051) AS legacy_press_rows
FROM pondolens.dev_gold.fact_regional_expenditure;
```

```sql
SELECT
    COUNT(*) AS row_count,
    COUNT(f.appropriation_amount) AS populated_appropriations,
    SUM(f.appropriation_amount) AS appropriation_php,
    SUM(f.obligation_amount) AS obligation_php
FROM pondolens.dev_gold.fact_regional_expenditure f
JOIN pondolens.dev_gold.dim_year y ON f.year_id = y.year_id
WHERE y.year = 2023 AND f.particular_id = 30033;
```

## Analytics rules

- NULL is not zero. Show missingness/status coverage alongside totals and rates.
- Do not sum rates, per-capita measures, or poverty thresholds across regions/years.
- Match observation years and verify geographic boundaries; source coverage varies between 17 and 18 regions.
- Aggregate expenditure to the required grain before joining indicator facts. Select a specific indicator definition to avoid repeated spending totals.
- Filter `geographic_level = 'region'` for regional comparisons. Do not allocate Nationwide/Central Office amounts to regions without a documented method.
- Review source coverage before adding national, office, and regional amounts together.
- Appropriations are not allotments. Obligations are not cash disbursements.
- Obligations above appropriations are not automatically evidence of overspending; verify legal coverage, timing, and budget basis before drawing conclusions.
- PCO alias consolidation resolves agency naming; it does not by itself establish execution-gap comparability or causation between spending and outcomes.

## Troubleshooting and maintenance

| Issue | Action |
| --- | --- |
| Temporary view not found | Run preparation statements in the same session; use saved-table checks for persistent state |
| Missing mapping | Inspect source labels/codes and update approved dimension/alias definitions |
| Duplicate normalized keys | Resolve the source collision; do not arbitrarily DISTINCT or sum financial rows |
| Legacy backup mismatch | Stop and inspect target history and backups; do not bypass the guard |
| Unexpected MERGE updates | Check changed sources, statuses, aliases, and the actual saved script version |
| Wrong target schema | Prepare an explicit migration; do not drop the fact as a routine fix |
| New particular | Allocate a new unused fixed ID; never reuse retired 30051 |

Keep SQL and documentation versioned together. Preserve original source evidence, configure job dependencies and alerts, parameterize environment paths before production deployment, and retain recovery evidence according to the team's retention policy.

Initial ID bases are table-specific. If the team requires exclusive cross-table numeric ranges, explicitly define capacity before future growth reaches another range.

Recorded development validation does not establish production scheduling, permissions, recovery testing, source-PDF accuracy, or statistical/geographic comparability. Gold-to-Silver reconciliation validates the implemented transformation, not independent original-source accuracy.
