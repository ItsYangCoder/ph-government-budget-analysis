# PondoLens: dim_indicator

| Document attribute | Value |
| --- | --- |
| Author | Christine Joy D. Balansay |
| Last updated | 2026-10-20 |
| Table | `pondolens.dev_gold.dim_indicator` |
| Layer / format | Gold / persistent Delta table |
| Initial registry | 19 definitions, IDs `40001–40019` |
| Implementation | Databricks SQL |
| Change strategy | Slowly Changing Dimension Type 1 |
| Status | Initial development load verified; production deployment acceptance pending |

## 1. Purpose and grain

`dim_indicator` provides stable identifiers and standardized definitions for development indicators used by PondoLens. It lets downstream facts reference an explicit measure, including its denominator, education level, sex group, or price basis where applicable.

**Grain: one row per distinct indicator definition.**

For example, poverty incidence among families and poverty incidence among population are separate definitions. Current-price GRDP per capita and constant-2018-price GRDP per capita are also separate definitions.

Region, observation year, and measured value belong in `fact_regional_indicator`. They are not dimension attributes. Silver source IDs such as `service_access_id` identify source observations and must not be used as `indicator_id`.

## 2. Data dictionary

| Column | SQL type | Nullable | Purpose and rule |
| --- | --- | --- | --- |
| `indicator_id` | `INT` | No | Fixed surrogate identifier. Must be unique and must never be reassigned to another definition. |
| `indicator` | `STRING` | No | Subject group: `unemployment`, `grdp_per_capita`, `health`, `poverty`, `education`, or `service_access`. Repetition is expected. |
| `measure_type` | `STRING` | No | Unique standardized definition identifier. Lowercase snake_case; includes distinguishing characteristics. |
| `unit` | `STRING` | No | Measurement unit, including denominator or price basis when needed. Exact labels are listed in the registry. |
| `processed_at` | `TIMESTAMP` | No | Insertion timestamp or timestamp of the latest changed descriptive attribute. Unchanged reruns preserve it. Session timezone is set to UTC. |

The implementation declares `NOT NULL` columns. It does **not** declare a primary-key constraint or a database-enforced unique constraint. ID and definition uniqueness are checked by pipeline assertions. A single scheduled writer is required to prevent competing loads from bypassing those checks.

## 3. Approved indicator registry

| `indicator_id` | `indicator` | `measure_type` | `unit` |
| ---: | --- | --- | --- |
| 40001 | unemployment | unemployment_rate | % of labor force |
| 40002 | grdp_per_capita | grdp_per_capita_current_prices | PHP/person |
| 40003 | grdp_per_capita | grdp_per_capita_constant_2018_prices | PHP/person (2018 prices) |
| 40004 | health | government_hospital_count | hospitals |
| 40005 | poverty | poverty_incidence_families | % of families |
| 40006 | poverty | poverty_incidence_population | % of population |
| 40007 | education | elementary_completion_rate_both_sexes | % |
| 40008 | education | elementary_completion_rate_male | % |
| 40009 | education | elementary_completion_rate_female | % |
| 40010 | education | junior_high_completion_rate_both_sexes | % |
| 40011 | education | junior_high_completion_rate_male | % |
| 40012 | education | junior_high_completion_rate_female | % |
| 40013 | education | senior_high_completion_rate_both_sexes | % |
| 40014 | education | senior_high_completion_rate_male | % |
| 40015 | education | senior_high_completion_rate_female | % |
| 40016 | poverty | annual_per_capita_poverty_threshold | PHP/person/year |
| 40017 | service_access | at_least_basic_drinking_water_access | % of families |
| 40018 | service_access | basic_sanitation_access | % of families |
| 40019 | service_access | basic_handwashing_facilities | % of consenting families |

### Definition notes

- **Unemployment:** values use the percentage scale; do not multiply values already expressed as percentages by 100 during fact loading.
- **GRDP per capita:** price-basis codes must be explicitly mapped from Silver. Do not assume the standardized definition name is the literal Silver label. Current and constant prices are separate series.
- **Hospitals:** the registered definition covers government hospitals. Verify the source ownership filter during fact loading; do not silently include private facilities.
- **Poverty incidence:** families and population have different denominators and must remain separate.
- **Poverty threshold:** annual Philippine pesos per person. The project owner reported Mia's confirmation of the original-source definition, including 2025. The underlying source/header was not re-inspected when preparing this document. Retain its reference with source documentation.
- **Service access:** drinking water and sanitation use `% of families`. Handwashing uses `% of consenting families`, not all families or households.
- **Education:** three levels × three sex groups produce nine definitions. `%` alone does not document the source formula or cohort; retain that methodology in the education dataset documentation.

## 4. Dependencies and scope

| Dependency | Role |
| --- | --- |
| `pondolens.dev_gold` | Existing target schema; the script does not create it. |
| `dim_indicator_seed` | Session-scoped approved registry defined using SQL `VALUES`. |
| `pondolens.dev_silver.service_access` | Direct dependency for checking three distinct measure/unit combinations. |
| Other indicator Silver datasets | Inputs to future fact loading; not directly read by the current dimension script. |
| `pondolens.dev_silver.shared_region_crosswalk` | Upstream dependency of service-access Silver preparation; not directly joined by this dimension script. |

The service-access Silver scope is PSA APIS, 2022 and 2024, regional Total records: 102 observations = 17 regions × 2 years × 3 measures. National observations are excluded from this Silver scope. These are source-coverage details, not additional dimension rows.

The dimension is a curated registry. It does not automatically discover all definitions from every Silver source, and successful creation does not establish complete source-to-fact coverage.

## 5. Loading design

Run the SQL statements in order in the same session:

1. Set the session timezone to UTC.
2. Create or replace the temporary seed view containing the approved definitions.
3. Assert the seed count, unique IDs, unique definitions, ID boundaries, and required values.
4. Check that Silver contains three distinct service-access measure/unit pairs and that each matches the registry.
5. Create the persistent Delta target if absent.
6. Validate target uniqueness and required attributes.
7. Reject any existing ID-to-definition or definition-to-ID conflict.
8. `MERGE` on `indicator_id`: insert missing rows; update changed `indicator` or `unit`; preserve unchanged rows.
9. Validate all 19 seed definitions against persisted rows and recheck uniqueness.
10. Display the registry and group counts for review.

The seed view is temporary; the final Delta table persists after the SQL session ends. `CREATE TABLE IF NOT EXISTS` does not migrate an incompatible existing schema.

### Idempotency and history

An unchanged rerun should insert zero rows, update zero rows, retain the same IDs, and preserve `processed_at`. Type 1 updates overwrite descriptive fields; no historical dimension versions are maintained.

The script does not delete target rows absent from the seed. Its post-load check validates the registered 19 rows and uniqueness across the target; it does not require the entire table to contain exactly 19 rows after future expansion.

### Transaction boundary

The Delta `MERGE` is the write operation. The surrounding assertions and DDL are separate statements, not one transaction covering the entire notebook. A failed post-load assertion does not roll back an already committed merge. Stop execution on errors and block downstream fact loads until the issue is resolved.

## 6. Validation contract

| Stage | Check | Expected |
| --- | --- | --- |
| Seed | Definition count | 19 in the current registry |
| Seed | Distinct IDs / distinct measure types | 19 / 19 |
| Seed | Minimum / maximum ID | 40001 / 40019 |
| Seed | Null or blank required attributes | 0 |
| Silver service access | Distinct measure/unit combinations | 3 |
| Silver service access | Combinations absent from seed | 0 |
| Target before write | Duplicate IDs or measure types | 0 |
| Target before write | Invalid required attributes | 0 |
| Mapping protection | Existing ID assigned to another definition | 0 |
| Mapping protection | Existing definition assigned another ID | 0 |
| Target after write | Seed definitions matching persisted attributes | 19 |
| Target after write | Duplicate IDs or measure types | 0 |

`ASSERT_TRUE` returns `NULL` on success; a `STOP` exception indicates a failed condition. This output is not a missing-value finding in the dimension.

## 7. Execution evidence

The following evidence was supplied by Christine Joy from the development execution on 2026-10-20:

| Observation | Reported result |
| --- | --- |
| Initial merge affected rows | 19 |
| Initial merge inserted / updated / deleted | 19 / 0 / 0 |
| Persisted IDs | 40001–40019 |
| Initial `processed_at` | 2026-10-20T09:57:05.559+00:00 |
| Validation statements | Successful `NULL` outputs; no error reported |
| Rerun | User reported completion; detailed merge metrics and timestamp comparison were not supplied. |

Expected group counts from the supplied output:

| Indicator | Definitions |
| --- | ---: |
| education | 9 |
| grdp_per_capita | 2 |
| health | 1 |
| poverty | 3 |
| service_access | 3 |
| unemployment | 1 |
| **Total** | **19** |

These results verify the initial development registry load. They do not constitute independent verification of the source accuracy, every Silver mapping, production permissions, or production scheduling.

## 8. Operator runbook

### Before running

1. Confirm the catalog/schema and compute environment.
2. Confirm read access to the service-access Silver table and write/create access to the Gold target as appropriate.
3. Run only one dimension writer at a time.
4. Use the reviewed SQL version from source control and execute in one session.
5. Ensure the job stops on a failed SQL statement and runs before dependent facts.

### After running

1. Retain job/run identifiers, assertion outcomes, merge metrics, and output counts with execution evidence.
2. Verify the 19 approved definitions.
3. For the first deployment, rerun without changing the seed and retain evidence of zero inserts, zero updates, stable IDs, and unchanged timestamps.
4. Release dependent fact loading only after all required checks pass.

### Troubleshooting

| Failure | Response |
| --- | --- |
| Temporary view not found | Rerun from the seed creation step in the same session. |
| Service-access definition/unit mismatch | Inspect Silver's distinct pairs and resolve the source contract; preserve the handwashing denominator. |
| Duplicate target ID or definition | Stop downstream loading; inspect duplicates and dependent fact references before repair. |
| ID/definition conflict | Restore the approved mapping in code; never renumber an existing definition to force the load. |
| Existing target schema mismatch | Inspect `DESCRIBE TABLE`; prepare a reviewed migration. Do not drop the table as a routine repair. |
| Failed post-load assertion | Investigate the committed table state and last write before retrying. |

## 9. Change management

- Add a new definition using a new unused fixed ID; never recycle retired IDs.
- Update registry checks, expected counts, documentation, and fact mappings together. The current assertions hard-code 19 definitions and the initial ID range.
- The present `measure_type` naming convention embeds level, sex, and price basis to make each definition unique. Keep future definitions equally explicit.
- Treat changes to denominator, scale, price basis, or meaning as semantic changes. Prefer a new definition/ID and reviewed fact mapping over changing the meaning of an existing ID.
- Use Type 1 updates for approved descriptive corrections only. Although the SQL permits unit updates, semantic unit changes require impact review.
- Do not drop or recreate this dimension after facts reference its IDs without a coordinated migration.
- Parameterize catalog/schema for deployment beyond development; the current script uses `pondolens.dev_gold` and `pondolens.dev_silver` literally.

## 10. Downstream fact contract

The intended fact grain is one location × observation year × indicator definition. Each fact row must resolve to exactly one `indicator_id` and valid location/year dimension keys.

Fact-loading requirements:

1. Explicitly map each source definition to this registry; do not infer the ID from source row numbers.
2. Reject missing or multiple dimension matches.
3. Validate measurements using source-specific rules, units, and scales.
4. Deduplicate the repeated poverty threshold across family/population source rows only after confirming values agree. Load one threshold per region/year; do not sum the repeated values.
5. Preserve distinct poverty incidence, education sex/level, and GRDP price-basis definitions.
6. Resolve differences in geographic coverage and boundaries explicitly. The 17-region service-access scope must not be assumed to match every other dataset automatically.
7. Do not sum percentages, per-capita measures, or poverty thresholds across regions or years. National estimates require appropriate source methodology and weights.
8. Confirm the actual fact and location/year dimension schemas before implementing the joins.

Fact loading is not part of the current dimension implementation.

## 11. Production acceptance

This document records the implemented controls; it does not label unverified operations as production-ready. Before production release, retain evidence for:

- A reviewed, version-controlled SQL implementation and immutable ID registry.
- Successful initial load and documented unchanged-rerun metrics.
- Explicit mappings and source validation for all six indicator groups.
- A configured single-writer job, failure alerts, and dimension-before-fact task dependency.
- Appropriate service-principal permissions and environment-specific paths.
- A reviewed recovery procedure and access to relevant Delta history for the configured retention period.

## 12. Platform references

- [Databricks: Upsert into a Delta Lake table using MERGE](https://docs.databricks.com/aws/en/delta/merge)
- [Databricks: assert_true function](https://docs.databricks.com/aws/en/sql/language-manual/functions/assert_true)

Platform references describe SQL behavior. Dataset methodology and original-source references belong in the corresponding Silver/source documentation.
