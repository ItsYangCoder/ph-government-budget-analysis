-- Poverty Incidence Silver
-- Source: pondolens.dev_bronze.poverty_incidence (PSA, 2021 / 2023 / 2025 only, no filled years)
-- Target: pondolens.dev_silver.poverty_incidence
-- Grain: one row per year + region_code + indicator (families and population are separate indicators).
-- Scope: regional rows only. National, province, district and city rows are excluded.
-- IDs start at 9,000,001 and stay the same on rerun. Run with max 1 concurrent job.

CREATE SCHEMA IF NOT EXISTS pondolens.dev_silver;

-- Stop if an older version of this table exists (it has no indicator column). Drop it first.
SELECT ASSERT_TRUE(
    COUNT(*) = 0 OR COUNT_IF(column_name = 'indicator') = 1,
    'Old poverty_incidence Silver schema found. Run DROP TABLE pondolens.dev_silver.poverty_incidence once, then rerun.'
)
FROM pondolens.information_schema.columns
WHERE table_schema = 'dev_silver'
  AND table_name = 'poverty_incidence';

CREATE TABLE IF NOT EXISTS pondolens.dev_silver.poverty_incidence (
    poverty_incidence_id BIGINT NOT NULL,
    year INT,
    region_code STRING,
    region_name STRING,
    indicator STRING,
    poverty_threshold_php DECIMAL(10, 2),
    poverty_incidence_pct DECIMAL(5, 2),
    estimate_marker STRING,
    display_value STRING,
    coefficient_of_variation DECIMAL(5, 2),
    standard_error DECIMAL(5, 2),
    ci_lower_pct DECIMAL(5, 2),
    ci_upper_pct DECIMAL(5, 2),
    unit STRING,
    value_status STRING,
    reliability_note STRING,
    sig_change_2021_2023 BOOLEAN,
    sig_change_2023_2025 BOOLEAN,
    revised_sulu_transfer BOOLEAN,
    revised_north_cotabato_transfer BOOLEAN,
    region_mapping_source STRING,
    notes STRING,
    source_page STRING,
    source_row INT,
    _processed_at TIMESTAMP,
    CONSTRAINT poverty_incidence_pk PRIMARY KEY (poverty_incidence_id)
)
USING DELTA;

-- Bronze rows must be unique before cleaning.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Duplicate poverty incidence Bronze keys (year, reference_unit, region, province).'
)
FROM (
    SELECT year, reference_unit, region, province
    FROM pondolens.dev_bronze.poverty_incidence
    GROUP BY year, reference_unit, region, province
    HAVING COUNT(*) > 1
) AS duplicate_bronze_keys;

-- Crosswalk aliases with their validity years.
-- Accepted spellings: source_region, code, name, "REGION <code>", and MIMAROPA variants.
CREATE OR REPLACE TEMP VIEW poverty_crosswalk_aliases AS
WITH crosswalk AS (
    SELECT
        UPPER(TRIM(source_region)) AS source_region,
        UPPER(TRIM(region_code)) AS region_code,
        MAX(UPPER(TRIM(region_name))) OVER (PARTITION BY UPPER(TRIM(region_code))) AS region_name,
        valid_from_year,
        valid_to_year
    FROM pondolens.dev_silver.shared_region_crosswalk
    WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
      AND NULLIF(TRIM(region_name), '') IS NOT NULL
      AND (LOWER(TRIM(geographic_level)) = 'region'
           OR (geographic_level IS NULL AND UPPER(TRIM(region_code)) NOT IN ('CO', 'NW', 'PHL')))
),
aliases AS (
    SELECT
        region_code,
        region_name,
        valid_from_year,
        valid_to_year,
        EXPLODE(ARRAY_COMPACT(ARRAY(
            source_region,
            region_code,
            region_name,
            CONCAT('REGION ', region_code),
            CASE WHEN region_code = 'IVB' THEN 'MIMAROPA' END,
            CASE WHEN region_code = 'IVB' THEN 'MIMAROPA REGION' END
        ))) AS region_alias
    FROM crosswalk
)
SELECT DISTINCT
    REGEXP_REPLACE(region_alias, r'[^A-Z0-9]', '') AS alias_key,
    region_code,
    region_name,
    valid_from_year,
    valid_to_year
FROM aliases
WHERE REGEXP_REPLACE(region_alias, r'[^A-Z0-9]', '') <> '';

-- Poverty-only mapping: PSA reports NIR for 2021 and 2023 (revised series),
-- but the shared crosswalk starts NIR later. Applied only here, the shared crosswalk is not changed.
CREATE OR REPLACE TEMP VIEW poverty_region_overrides AS
SELECT * FROM VALUES
    ('NEGROSISLANDREGION', 2021, 'NIR'),
    ('NEGROSISLANDREGION', 2023, 'NIR'),
    ('NIR', 2021, 'NIR'),
    ('NIR', 2023, 'NIR')
AS o(alias_key, year, region_code);

-- Override codes must exist in the crosswalk so they get the standard name.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Override region code not found in shared_region_crosswalk.'
)
FROM poverty_region_overrides AS o
LEFT ANTI JOIN poverty_crosswalk_aliases AS a
    ON o.region_code = a.region_code;

-- Clean text, cast numbers and split note codes. Regional rows only.
-- The Bronze region and region_name columns are swapped for NCR, CAR, NIR and BARMM, so both are match keys.
CREATE OR REPLACE TEMP VIEW poverty_bronze_clean AS
WITH regional AS (
    SELECT
        TRY_CAST(TRIM(year) AS INT) AS year,
        CASE
            WHEN LOWER(reference_unit) LIKE '%families%' THEN 'poverty_incidence_families'
            WHEN LOWER(reference_unit) LIKE '%population%' THEN 'poverty_incidence_population'
        END AS indicator,
        NULLIF(REGEXP_REPLACE(UPPER(TRIM(region)), r'[^A-Z0-9]', ''), '') AS region_key,
        NULLIF(REGEXP_REPLACE(UPPER(TRIM(region_name)), r'[^A-Z0-9]', ''), '') AS region_name_key,
        TRIM(poverty_incidence_coeff_var) AS cv_raw,
        REPLACE(TRIM(annual_poverty_threshold_per_capita), ',', '') AS threshold_txt,
        TRIM(poverty_incidence_estimate) AS estimate_txt,
        TRIM(poverty_incidence_standard_error) AS se_txt,
        TRIM(poverty_incidence_confidence_lower) AS ci_lower_txt,
        TRIM(poverty_incidence_confidence_upper) AS ci_upper_txt,
        NULLIF(TRIM(notes), '') AS notes,
        TRANSFORM(SPLIT(COALESCE(notes, ''), ','), x -> TRIM(x)) AS note_codes,
        TRIM(source_page) AS source_page,
        TRY_CAST(TRIM(source_row) AS INT) AS source_row
    FROM pondolens.dev_bronze.poverty_incidence
    WHERE UPPER(TRIM(region)) <> 'PHILIPPINES'
      AND NULLIF(TRIM(province), '') IS NULL
)
SELECT
    *,
    -- Dash in CV becomes NULL.
    CASE WHEN cv_raw IN ('-', '–', '—', '') THEN NULL ELSE cv_raw END AS cv_txt,
    TRY_CAST(threshold_txt AS DECIMAL(10, 2)) AS poverty_threshold_php,
    TRY_CAST(estimate_txt AS DECIMAL(5, 2)) AS poverty_incidence_pct,
    TRY_CAST(CASE WHEN cv_raw IN ('-', '–', '—', '') THEN NULL ELSE cv_raw END AS DECIMAL(5, 2)) AS coefficient_of_variation,
    TRY_CAST(se_txt AS DECIMAL(5, 2)) AS standard_error,
    TRY_CAST(ci_lower_txt AS DECIMAL(5, 2)) AS ci_lower_pct,
    TRY_CAST(ci_upper_txt AS DECIMAL(5, 2)) AS ci_upper_pct
FROM regional;

-- Map each row to one region valid for its year.
-- Priority: region column match, then region_name column match, then the poverty-only override.
CREATE OR REPLACE TEMP VIEW poverty_mapping_candidates AS
WITH candidates AS (
    SELECT
        c.*,
        a.region_code AS xw_region_code,
        a.region_name AS xw_region_name,
        CASE WHEN c.region_key = a.alias_key THEN 1 ELSE 2 END AS match_priority
    FROM poverty_bronze_clean AS c
    LEFT JOIN poverty_crosswalk_aliases AS a
        ON (c.region_key = a.alias_key OR c.region_name_key = a.alias_key)
       AND c.year BETWEEN COALESCE(a.valid_from_year, 1900) AND COALESCE(a.valid_to_year, 9999)
)
SELECT
    *,
    DENSE_RANK() OVER (
        PARTITION BY year, indicator, region_key, region_name_key
        ORDER BY match_priority
    ) AS match_rank
FROM candidates;

-- Do not choose between conflicting best matches.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Ambiguous poverty region mapping: review crosswalk codes/names.'
)
FROM (
    SELECT year, indicator, region_key, region_name_key
    FROM poverty_mapping_candidates
    WHERE match_rank = 1 AND xw_region_code IS NOT NULL
    GROUP BY year, indicator, region_key, region_name_key
    HAVING COUNT(DISTINCT xw_region_code) > 1
) AS ambiguous;

CREATE OR REPLACE TEMP VIEW poverty_mapped AS
WITH best AS (
    SELECT DISTINCT * EXCEPT (match_priority, match_rank)
    FROM poverty_mapping_candidates
    WHERE match_rank = 1
),
override AS (
    SELECT DISTINCT
        o.alias_key,
        o.year,
        o.region_code,
        a.region_name
    FROM poverty_region_overrides AS o
    INNER JOIN (SELECT DISTINCT region_code, region_name FROM poverty_crosswalk_aliases) AS a
        ON o.region_code = a.region_code
)
SELECT
    b.* EXCEPT (xw_region_code, xw_region_name),
    COALESCE(b.xw_region_code, o1.region_code, o2.region_code) AS region_code,
    COALESCE(b.xw_region_name, o1.region_name, o2.region_name) AS region_name,
    CASE
        WHEN b.xw_region_code IS NOT NULL THEN 'shared_region_crosswalk'
        WHEN COALESCE(o1.region_code, o2.region_code) IS NOT NULL THEN 'poverty_override'
    END AS region_mapping_source
FROM best AS b
LEFT JOIN override AS o1
    ON b.region_key = o1.alias_key AND b.year = o1.year
LEFT JOIN override AS o2
    ON b.region_name_key = o2.alias_key AND b.year = o2.year
   AND o1.region_code IS NULL;

-- List Bronze rows that cannot be loaded and their reasons.
CREATE OR REPLACE TEMP VIEW poverty_rejected AS
SELECT *
FROM (
    SELECT
        year,
        indicator,
        region_key,
        region_name_key,
        estimate_txt,
        cv_raw,
        source_page,
        source_row,
        CONCAT_WS(
            '; ',
            CASE WHEN region_code IS NULL THEN 'unmapped region for this year' END,
            CASE WHEN year IS NULL OR year NOT IN (2021, 2023, 2025) THEN 'unexpected year' END,
            CASE WHEN indicator IS NULL THEN 'unknown reference_unit' END,
            CASE WHEN poverty_threshold_php IS NULL OR poverty_threshold_php <= 0 THEN 'invalid threshold' END,
            CASE WHEN poverty_incidence_pct IS NULL THEN 'missing or invalid estimate' END,
            CASE WHEN poverty_incidence_pct < 0 OR poverty_incidence_pct > 100 THEN 'estimate outside 0-100' END,
            CASE WHEN cv_txt IS NOT NULL AND coefficient_of_variation IS NULL THEN 'invalid CV' END,
            CASE WHEN coefficient_of_variation IS NULL AND poverty_incidence_pct <> 0 THEN 'missing CV on non-zero estimate' END,
            CASE WHEN standard_error IS NULL OR ci_lower_pct IS NULL OR ci_upper_pct IS NULL THEN 'missing SE or CI' END,
            CASE WHEN poverty_incidence_pct < ci_lower_pct OR poverty_incidence_pct > ci_upper_pct THEN 'estimate outside CI' END
        ) AS rejection_reason
    FROM poverty_mapped
) AS rejected
WHERE rejection_reason <> '';

-- To inspect rejected rows: SELECT * FROM poverty_rejected.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Rejected Bronze rows found (region, year, unit or numbers). See poverty_rejected.'
)
FROM poverty_rejected;

-- Silver rows. c/ estimates keep a "<0.05%" marker. CV above 10 gets "use with caution".
CREATE OR REPLACE TEMP VIEW poverty_stage AS
SELECT
    year,
    region_code,
    region_name,
    indicator,
    poverty_threshold_php,
    poverty_incidence_pct,
    CASE
        WHEN ARRAY_CONTAINS(note_codes, 'c/') AND poverty_incidence_pct < 0.05 THEN '<0.05%'
    END AS estimate_marker,
    CASE
        WHEN ARRAY_CONTAINS(note_codes, 'c/') AND poverty_incidence_pct < 0.05 THEN '<0.05%'
        ELSE CONCAT(FORMAT_NUMBER(poverty_incidence_pct, 1), '%')
    END AS display_value,
    coefficient_of_variation,
    standard_error,
    ci_lower_pct,
    ci_upper_pct,
    CASE
        WHEN indicator = 'poverty_incidence_families' THEN '% of families'
        ELSE '% of population'
    END AS unit,
    CASE
        WHEN ARRAY_CONTAINS(note_codes, 'c/') AND poverty_incidence_pct < 0.05 THEN 'below_0_05_pct'
        ELSE 'available'
    END AS value_status,
    CASE WHEN coefficient_of_variation > 10 THEN 'use with caution' END AS reliability_note,
    ARRAY_CONTAINS(note_codes, '1/') AS sig_change_2021_2023,
    ARRAY_CONTAINS(note_codes, '2/') AS sig_change_2023_2025,
    ARRAY_CONTAINS(note_codes, 'r1/') AS revised_sulu_transfer,
    ARRAY_CONTAINS(note_codes, 'r2/') AS revised_north_cotabato_transfer,
    region_mapping_source,
    notes,
    source_page,
    source_row
FROM poverty_mapped;

-- Mapping must keep every regional Bronze row exactly once.
SELECT ASSERT_TRUE(
    (SELECT COUNT(*) FROM poverty_stage) = (SELECT COUNT(*) FROM poverty_bronze_clean),
    'Region mapping changed the poverty incidence row count.'
);

-- No duplicates per year, region code and indicator.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Duplicate year/region_code/indicator keys found in poverty_stage.'
)
FROM (
    SELECT year, region_code, indicator
    FROM poverty_stage
    GROUP BY year, region_code, indicator
    HAVING COUNT(*) > 1
) AS duplicate_stage_keys;

-- Check existing IDs before merging.
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT poverty_incidence_id)
    AND COUNT_IF(poverty_incidence_id < 9000001) = 0,
    'Duplicate IDs, or IDs below 9000001.'
)
FROM pondolens.dev_silver.poverty_incidence;

-- Existing Silver keys must be unique so each one keeps one ID.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Duplicate year/region_code/indicator keys in the Silver target.'
)
FROM (
    SELECT year, region_code, indicator
    FROM pondolens.dev_silver.poverty_incidence
    GROUP BY year, region_code, indicator
    HAVING COUNT(*) > 1
) AS duplicate_target_keys;

-- Stop if a Bronze year contains under 80% of its existing Silver rows.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'A Bronze year has under 80% of the Silver rows; possible partial load.'
)
FROM (
    SELECT t.year
    FROM pondolens.dev_silver.poverty_incidence AS t
    INNER JOIN (
        SELECT year, COUNT(*) AS n
        FROM poverty_stage
        GROUP BY year
    ) AS s
        ON t.year = s.year
    GROUP BY t.year, s.n
    HAVING s.n < 0.8 * COUNT(*)
) AS partial_loads;

-- Only new keys receive a new ID. Start at 9000001 or continue from the highest ID.
CREATE OR REPLACE TEMP VIEW poverty_numbered AS
WITH new_records AS (
    SELECT s.*
    FROM poverty_stage AS s
    LEFT ANTI JOIN pondolens.dev_silver.poverty_incidence AS t
        ON s.year = t.year
        AND s.region_code = t.region_code
        AND s.indicator = t.indicator
),
last_id AS (
    SELECT COALESCE(MAX(poverty_incidence_id), CAST(9000000 AS BIGINT)) AS last_number
    FROM pondolens.dev_silver.poverty_incidence
)
SELECT
    s.*,
    l.last_number + ROW_NUMBER() OVER (
        ORDER BY s.year, s.indicator, s.region_code
    ) AS next_id
FROM new_records AS s
CROSS JOIN last_id AS l;

CREATE OR REPLACE TEMP VIEW poverty_merge_source AS

-- Existing keys keep their IDs.
SELECT t.poverty_incidence_id, s.*, FALSE AS removed
FROM poverty_stage AS s
INNER JOIN pondolens.dev_silver.poverty_incidence AS t
    ON s.year = t.year
    AND s.region_code = t.region_code
    AND s.indicator = t.indicator

UNION ALL

-- New keys get the next IDs.
SELECT n.next_id, n.* EXCEPT (next_id), FALSE AS removed
FROM poverty_numbered AS n

UNION ALL

-- Remove Silver rows missing from Bronze for years in this load.
SELECT
    t.poverty_incidence_id,
    t.year, t.region_code, t.region_name, t.indicator,
    t.poverty_threshold_php, t.poverty_incidence_pct, t.estimate_marker, t.display_value,
    t.coefficient_of_variation, t.standard_error, t.ci_lower_pct, t.ci_upper_pct,
    t.unit, t.value_status, t.reliability_note,
    t.sig_change_2021_2023, t.sig_change_2023_2025,
    t.revised_sulu_transfer, t.revised_north_cotabato_transfer,
    t.region_mapping_source, t.notes, t.source_page, t.source_row,
    TRUE AS removed
FROM pondolens.dev_silver.poverty_incidence AS t
LEFT SEMI JOIN (SELECT DISTINCT year FROM poverty_stage) AS y
    ON t.year = y.year
LEFT ANTI JOIN poverty_stage AS s
    ON t.year = s.year
    AND t.region_code = s.region_code
    AND t.indicator = s.indicator;

MERGE INTO pondolens.dev_silver.poverty_incidence AS t
USING poverty_merge_source AS s
ON t.poverty_incidence_id = s.poverty_incidence_id

WHEN MATCHED AND s.removed
THEN DELETE

WHEN MATCHED AND NOT s.removed AND NOT (
    t.region_name <=> s.region_name
    AND t.poverty_threshold_php <=> s.poverty_threshold_php
    AND t.poverty_incidence_pct <=> s.poverty_incidence_pct
    AND t.estimate_marker <=> s.estimate_marker
    AND t.display_value <=> s.display_value
    AND t.coefficient_of_variation <=> s.coefficient_of_variation
    AND t.standard_error <=> s.standard_error
    AND t.ci_lower_pct <=> s.ci_lower_pct
    AND t.ci_upper_pct <=> s.ci_upper_pct
    AND t.unit <=> s.unit
    AND t.value_status <=> s.value_status
    AND t.reliability_note <=> s.reliability_note
    AND t.region_mapping_source <=> s.region_mapping_source
    AND t.notes <=> s.notes
    AND t.source_page <=> s.source_page
    AND t.source_row <=> s.source_row
)
THEN UPDATE SET
    t.region_name = s.region_name,
    t.poverty_threshold_php = s.poverty_threshold_php,
    t.poverty_incidence_pct = s.poverty_incidence_pct,
    t.estimate_marker = s.estimate_marker,
    t.display_value = s.display_value,
    t.coefficient_of_variation = s.coefficient_of_variation,
    t.standard_error = s.standard_error,
    t.ci_lower_pct = s.ci_lower_pct,
    t.ci_upper_pct = s.ci_upper_pct,
    t.unit = s.unit,
    t.value_status = s.value_status,
    t.reliability_note = s.reliability_note,
    t.sig_change_2021_2023 = s.sig_change_2021_2023,
    t.sig_change_2023_2025 = s.sig_change_2023_2025,
    t.revised_sulu_transfer = s.revised_sulu_transfer,
    t.revised_north_cotabato_transfer = s.revised_north_cotabato_transfer,
    t.region_mapping_source = s.region_mapping_source,
    t.notes = s.notes,
    t.source_page = s.source_page,
    t.source_row = s.source_row,
    t._processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED AND NOT s.removed
THEN INSERT (
    poverty_incidence_id, year, region_code, region_name, indicator,
    poverty_threshold_php, poverty_incidence_pct, estimate_marker, display_value,
    coefficient_of_variation, standard_error, ci_lower_pct, ci_upper_pct,
    unit, value_status, reliability_note,
    sig_change_2021_2023, sig_change_2023_2025,
    revised_sulu_transfer, revised_north_cotabato_transfer,
    region_mapping_source, notes, source_page, source_row, _processed_at
)
VALUES (
    s.poverty_incidence_id, s.year, s.region_code, s.region_name, s.indicator,
    s.poverty_threshold_php, s.poverty_incidence_pct, s.estimate_marker, s.display_value,
    s.coefficient_of_variation, s.standard_error, s.ci_lower_pct, s.ci_upper_pct,
    s.unit, s.value_status, s.reliability_note,
    s.sig_change_2021_2023, s.sig_change_2023_2025,
    s.revised_sulu_transfer, s.revised_north_cotabato_transfer,
    s.region_mapping_source, s.notes, s.source_page, s.source_row, CURRENT_TIMESTAMP()
);

-- Final check. Expected: 108 rows (18 regions x 3 years x 2 indicators), 4 NIR override rows (2021, 2023),
-- 4 "use with caution" rows (NCR and Region I, 2025), 0 "<0.05%" rows at regional level.
SELECT
    COUNT(*) AS silver_rows,
    COUNT(DISTINCT poverty_incidence_id) AS distinct_ids,
    MIN(poverty_incidence_id) AS first_id,
    MAX(poverty_incidence_id) AS last_id,
    COUNT(DISTINCT region_code) AS regions,
    CONCAT_WS(', ', ARRAY_SORT(COLLECT_SET(CAST(year AS STRING)))) AS years,
    COUNT_IF(region_mapping_source = 'poverty_override') AS override_rows,
    COUNT_IF(reliability_note = 'use with caution') AS use_with_caution_rows,
    COUNT_IF(estimate_marker = '<0.05%') AS below_0_05_rows
FROM pondolens.dev_silver.poverty_incidence;
