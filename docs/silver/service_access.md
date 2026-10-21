# Service Access — Silver

Documented by: **Christine Joy Balansay**  
Updated: 22 October 2026 (Asia/Manila)  
Table: `pondolens.dev_silver.service_access`  
Source: PSA APIS observations in Bronze

## Purpose

Stores regional access to drinking water, sanitation, and handwashing facilities. Each measure keeps its correct unit and family denominator.

One row represents **one region + year + service_measure**. The model selects PSA APIS records for **2022 and 2024**, with 17 regions and three measures per year: **102 records**. National observations, other sources, and other years remain in Bronze. NIR observations are not created.

## Data dictionary

| Column | Type | Meaning |
|---|---|---|
| service_access_id | INT | Record ID starting at 400,000,001. Existing business keys keep their IDs on rerun. |
| year | INT | Observation year: 2022 or 2024. |
| service | STRING | water, sanitation, or hygiene. |
| service_measure | STRING | Standard measure name from the mapping below. |
| region_name | STRING | Region name from the shared crosswalk. |
| region_code | STRING | Region code from the shared crosswalk. |
| breakdown_type | STRING | Total for all selected records. |
| breakdown_value | STRING | All families or Consenting families, depending on the measure. |
| value | DOUBLE | Percentage value between 0 and 100. A value of 95 means 95%. |
| unit | STRING | % of families or % of consenting families. |
| processed_at | TIMESTAMP | Time the record was inserted or changed. Unchanged records retain their timestamp. |

All columns are required. The unique record ID is `service_access_id`; the MERGE business key is `(region_code, year, service_measure)`. Total breakdown is fixed for this model.

## Measure mapping

| Source indicator | service | service_measure | Denominator |
|---|---|---|---|
| At least basic drinking-water access | water | at_least_basic_drinking_water_access | All families |
| Basic sanitation access | sanitation | basic_sanitation_access | All families |
| Basic handwashing facilities | hygiene | basic_handwashing_facilities | Consenting families |

Handwashing uses consenting families, so its denominator differs from the other two measures. This model does not include electricity or internet access.

## Transformation rules

- Select the exact PSA APIS source label, the two supported years, and the three source indicators above.
- Exclude National and Philippines area labels. Require country to be Philippines and breakdown_type to be Total.
- Trim source labels and parse years and measurements as decimals for validation. Store year as INT and the validated measurement as DOUBLE.
- Match source region names to crosswalk aliases using trimmed, case-insensitive text and the observation year within the crosswalk validity dates.
- Collapse identical code/name mappings and reject missing or conflicting mappings. No fallback or historical NIR override is applied.
- Map source indicators to standard service labels. Preserve units and breakdown values.
- Keep original source notes and ingestion metadata in Bronze. Missing measurements are rejected within the selected scope; no values are filled with zero.

## Quality checks

Before loading, the SQL requires:

- Exactly 102 selected records.
- Valid country, region, year, numeric percentage, unit, and denominator labels.
- No unexpected rescued payload.
- Unique source region/year/indicator keys.
- Exactly one distinct crosswalk code/name mapping per source region and year.
- Unique clean region/year/measure keys.
- Exactly six year/measure groups, each with 17 records and 17 distinct regions.
- Unique, non-null existing IDs of at least 400,000,001 and unique existing business keys.

After the MERGE, the SQL checks that all 102 clean records match the stored target values and have IDs and processing timestamps. The final output reports counts and value ranges by year and measure.

[dbt tests](../../dbt/models/silver/schema.yml) also check nonempty output, required columns, unique IDs, and the documented grain including breakdown fields.

## Load and rerun behavior

The model uses a Delta MERGE on region_code, year, and service_measure. New records receive IDs after the current maximum. Changed values or attributes update the existing record. Unchanged records keep their IDs and processed_at.

The model does not delete target records absent from the selected source. Post-load matching validates selected records, not the absence of extra target records.

Run through dbt after successful Bronze ingestion and crosswalk preparation, with **one concurrent writer**. The SQL sets the session time zone to UTC. dbt resolves the destination catalog and schema from the environment configuration.

The 102-record coverage rule is fixed in the current SQL. Supporting additional years, regions, or measures requires updating that contract before loading them.

For failed runs, follow [pipeline recovery](../ingestion.md#pipeline-failures-and-recovery).

## Usage notes

- Compare the same measure and year across regions. Do not sum percentages or average them to create a national estimate.
- Do not use population totals as weights for family or consenting-family percentages.
- Keep missing years missing. Do not carry 2022 or 2024 values into other years.
- Review the source notes for survey status, water-measure derivation, and geographic coverage. Those notes are retained in Bronze rather than dedicated Silver columns.
- The profiled source notes describe 2022 as final and 2024 as preliminary. The Silver table has no estimate-status column.
- Source geography includes notes about Sulu and the absence of separate NIR observations. Confirm boundary compatibility before comparing with budget or population data.
- Service-access percentages describe reported access; they do not by themselves establish service quality or the effect of government spending.

## Related files

- [Silver transformation SQL](../../dbt/models/silver/service_access.sql)
- [Silver column definitions and dbt tests](../../dbt/models/silver/schema.yml)
- [Bronze profiling SQL](../../profiling/bronze/service_access/profiling.sql)
- [Bronze data dictionary](../../profiling/bronze/service_access/data_dictionary.md)
- [Bronze findings](../../profiling/bronze/service_access/findings.md)
- [Shared region crosswalk](../shared_region_crosswalk.md)
