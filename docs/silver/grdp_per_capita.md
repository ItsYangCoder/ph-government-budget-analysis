# GRDP per Capita — Silver Documentation

Assigned to: Anjelika Marquez  
Updated: 20 October 2026 (Asia/Manila)  
Source: `pondolens.dev_bronze.grdp_per_capita`  
Reference: `pondolens.dev_silver.shared_region_crosswalk`  
Target: `pondolens.dev_silver.grdp_per_capita`  
SQL: `dbt/models/silver/grdp_per_capita.sql`  
Scope: source year labels 2021–2025

## Purpose and grain

Standardize regional and national economic output per person for analysis by year and price basis. Values are expressed in Philippine pesos per person.

One row represents **year × region_code × price_basis × geographic_level**. This combination is the natural key. `grdp_per_capita_id` is the surrogate identifier.

GRDP per capita is distinct from total GRDP and household income. Regional values are not additive.

## Output data dictionary

| Column | Type | Description |
|---|---|---|
| grdp_per_capita_id | BIGINT | Surrogate ID starting at 100,000,001; preserved for existing matched natural keys. |
| region_code | STRING | Canonical project code from the shared crosswalk. PHL identifies the Philippines; these are project codes, not official PSGC codes. |
| region_name | STRING | Canonical name supplied by the crosswalk. |
| year | INT | Source observation year, currently 2021–2025. |
| grdp_per_capita | DECIMAL(20,6) | Positive economic output per person in Philippine pesos, stored to six decimal places. |
| price_basis | INT | 2018 for constant 2018 prices; the observation year for current prices. |
| geographic_level | STRING | national for PHL; region for regional observations. |
| processed_at | TIMESTAMP | Processing timestamp assigned when the record is inserted or its name or amount changes. |

All eight columns are declared NOT NULL by the creation script. `processed_at` is the only audit field in Silver. Source labels, original measure text, and ingestion metadata remain in Bronze.

Six-decimal storage applies rounding and does not preserve every decimal digit of the source. No multiplication by 1,000 is applied.

## Value statuses

The target does not contain a value_status column. Input validation determines whether a record can be loaded.

| Input condition | Treatment |
|---|---|
| Positive numeric amount representable as DECIMAL(20,6) | Accept. |
| Missing or unparseable amount | Block the load. |
| Zero or negative amount | Block the load. |
| Unexpected unit or price-basis label | Block the load. |
| Missing or unsupported geographic level | Block the load. |
| Unmapped or conflicting geographic identity | Block the load. |
| Nonblank rescued-data payload | Block the load. |

Missing measures are not converted to zero or silently excluded from the selected source scope.

## Transformation rules

1. Validate full-source year labels before applying the project filter. Year text must contain four digits.
2. Retain observations within 2021–2025. The remaining Bronze history stays available upstream.
3. Trim labels and normalize source geography into uppercase alphanumeric lookup keys.
4. Parse measure text using decimal arithmetic and store the value as DECIMAL(20,6).
5. Validate the unit as Philippine pesos per person and retain that scale.
6. Build distinct canonical regions from the shared crosswalk, excluding Central Office and Nationwide allocation codes.
7. Match source codes and names using source aliases, canonical names, and canonical codes. Equivalent lookup entries are collapsed; conflicting aliases block the load.
8. Require a recognized source code when one is provided. When both source code and name resolve, their region codes must agree. Blank codes are resolved by name, including MIMAROPA and Philippines.
9. Standardize source country observations to national with code PHL. Regional observations retain region as their geographic level.
10. Encode constant 2018 prices as 2018 and current prices as the observation year.
11. Validate mapped observation counts and natural-key uniqueness before merging.
12. Assign IDs only to new keys and record processed_at for inserted or changed records.

The transformation uses `source_region`, `region_code`, `region_name`, `valid_from_year`, `valid_to_year`, and `geographic_level` from the crosswalk. It does not use source_code as a separate lookup or filter.

### Crosswalk periods and historical NIR

The script separately checks whether the canonical region code has an applicable crosswalk interval for the observation year. Canonical aliases identify geography; this interval check is at code level, not an effective-dated alias join.

A narrowly scoped preservation exception accepts NIR observations for 2021–2023 only when source_name is exactly:

`2018-2025 GRDP_Reg_(with NIR as of April 2026)`

This retains six source observations: three years × two price bases. The shared crosswalk validity dates remain unchanged. The exception preserves source-reported regional identity; it does not verify historical boundary comparability.

A different historical source label outside the applicable intervals requires review. Verify the workbook's geographic revision notes before joining historical NIR, VI, and VII measures to regional budget data.

## IDs and load behavior

- The initial ID base is 100,000,000; the first assigned ID is 100,000,001.
- Existing matched natural keys retain their IDs.
- New keys receive IDs above the current target maximum, ordered by year, region code, price basis, and geographic level.
- Allocation uses BIGINT with an overflow check.
- Sequential allocation requires one concurrent writer and stable inputs during execution.
- The offset is a project identifier convention, not a global uniqueness guarantee across tables.

| Source/target situation | Action |
|---|---|
| Natural key exists with unchanged name and amount | Preserve the record, ID, and processed_at. |
| Natural key exists with a corrected name or amount | Update those attributes and processed_at; preserve ID. |
| New valid natural key | Insert with a newly allocated ID and processed_at. |
| Previously loaded record absent from the current source | Preserve the existing record. |
| Invalid input or conflicting mapping | Fail validation before MERGE. |
| A source correction changes a natural-key field | Treat it as a new key; review the previously loaded key separately. |

The script evaluates the current source within the configured scope on each run. It does not use an ingestion watermark. Preserve existing IDs during routine refreshes; external table resets or manual changes can affect future ID allocation.

## Target creation and schema cleanup

The SQL creates the Silver schema and target table when absent. It retains an existing table and does not automatically migrate incompatible schemas.

Before loading, a metadata check requires the target amount column to be DECIMAL(20,6). An earlier BIGINT target needs a reviewed schema migration; the script does not silently load decimal amounts into it.

Provisioning and MERGE are separate operations. Table creation can remain if a later statement fails. Run in order and stop on the first failed statement.

The final SQL referenced by this document is the eight-column decimal version. The earlier branch version containing a BIGINT measure and processing_run_id is a different implementation and must be replaced before repository deployment.

## Validation gates

The SQL checks:

- Four-digit full-source year labels before filtering.
- A nonempty 2021–2025 source scope.
- Required source names, valid geographic levels, supported units, and price bases.
- Positive, parseable measures within the target decimal capacity.
- No nonblank rescued-data payloads in the selected scope.
- Unambiguous canonical region names and normalized aliases.
- Successful geographic mapping and agreement between resolved source code and name.
- Applicable canonical-code validity intervals or the explicit historical NIR exception.
- Preservation of source observation count after mapping.
- Unique staged and existing target natural keys.
- Valid, unique existing IDs and required target values.
- BIGINT ID allocation without overflow.
- Agreement between current staged observations and matching target records after MERGE.

These checks do not independently verify the original workbook, complete ingestion coverage, or historical boundary equivalence.

## Recorded validation results

The owner supplied the following Databricks target results on 20 October 2026:

| Check | Observed result |
|---|---:|
| Total rows | 185 |
| Unique IDs | 185 |
| First ID | 100,000,001 |
| Last ID | 100,000,185 |
| Unmapped rows in the reported check | 0 |
| Missing amounts | 0 |
| Nonpositive amounts | 0 |
| Duplicate natural keys | 0 |

The supplied DESCRIBE output confirms the eight columns and types listed in the output data dictionary, including BIGINT identifiers and DECIMAL(20,6) amounts.

| Year | Price basis | Geographic level | Rows |
|---|---:|---|---:|
| 2021 | 2018 | region | 18 |
| 2021 | 2021 | national | 1 |
| 2021 | 2021 | region | 18 |
| 2022 | 2018 | region | 18 |
| 2022 | 2022 | national | 1 |
| 2022 | 2022 | region | 18 |
| 2023 | 2018 | region | 18 |
| 2023 | 2023 | national | 1 |
| 2023 | 2023 | region | 18 |
| 2024 | 2018 | region | 18 |
| 2024 | 2024 | national | 1 |
| 2024 | 2024 | region | 18 |
| 2025 | 2018 | region | 18 |
| 2025 | 2025 | national | 1 |
| 2025 | 2025 | region | 18 |

The snapshot contains 90 regional constant-price observations, 90 regional current-price observations, and five national current-price observations. There are no supplied national constant-price observations.

These results validate the reported target snapshot. They do not independently establish rerun behavior, unchanged timestamps, recovery, or the exact script revision executed. The 185-row baseline is not a permanent limit for future valid additions.

## Job execution

1. Complete Bronze ingestion and shared crosswalk maintenance successfully.
2. Use the final eight-column decimal SQL version and confirm the intended environment names.
3. Execute all statements in order within one SQL session, stopping on the first error.
4. Set maximum concurrent runs to 1 and prevent other target writers.
5. Keep Bronze and the crosswalk stable while the script runs; temporary views read underlying tables.
6. Check target schema, IDs, natural keys, coverage, and stage-to-target reconciliation.
7. Retain query outputs and Job execution evidence with the deployed revision.

The SQL uses explicit pondolens.dev_* names. It is a multi-statement Databricks SQL script stored under the dbt directory, not a ready-to-run dbt SELECT model. The runtime must support the script's SQL functions and Delta MERGE; the execution identity needs input reads and target provisioning/write permissions.

Before unattended scheduling, verify in an isolated schema that an unchanged rerun preserves IDs, row count, and timestamps; a corrected measure updates its existing ID; a new key inserts once; and invalid inputs block the merge. Record those results separately from the initial load.

On failure, stop dependent processing, investigate the assertion, correct the responsible input or mapping, and rerun the complete script. Preserve existing target identifiers.

## Analytical limitations

- Values represent economic output per person, not household income or individual earnings.
- Do not sum regional per-capita measures or derive a national value from a simple regional average. Use supplied national observations where available.
- Filter an explicit price basis; do not combine current and constant prices as additive measures.
- National constant-price observations are absent from this snapshot. Do not manufacture them from unweighted regional averages.
- Historical NIR preservation does not establish boundary compatibility with budget or other indicator datasets.
- Six-decimal storage rounds the source values; original precision remains in Bronze.
- The project scope is 2021–2025. New years require a reviewed filter change and updated checks. Extending to 2018 also requires a separate basis category because both numeric basis encodings would equal 2018.
- Comparisons with spending describe associations and do not establish causation.
- Verify source authority and geographic revision methodology against the original publication before final interpretation.

## Related files

- [Bronze profiling](../../profiling/bronze/grdp_per_capita/profiling.sql)
- [Bronze findings](../../profiling/bronze/grdp_per_capita/findings.md)
- [Bronze data dictionary](../../profiling/bronze/grdp_per_capita/data_dictionary.md)
- [GRDP per capita Silver SQL](../../dbt/models/silver/grdp_per_capita.sql)

Repository destination: `docs/silver/grdp_per_capita.md`.
