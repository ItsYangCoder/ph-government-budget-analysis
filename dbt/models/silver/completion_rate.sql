{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- Completion Rate Silver
-- Scope: 2021–2025. IDs start at 8,000,001.
-- Run after complete Bronze ingestion, with one concurrent target writer.
-- Crosswalk: source_region, region_code, region_name,
-- valid_from_year, valid_to_year, source_code, geographic_level.

CREATE SCHEMA IF NOT EXISTS {{ this.database }}.{{ this.schema }}
-- pondolens:statement --
-- Source rows must be unique before alias resolution.
SELECT assert_true(COUNT(*) = 0, 'Duplicate completion rate Bronze keys.')
FROM (
    SELECT indicator, geolocation, level_of_education, sex
    FROM {{ source('bronze', 'completion_rate') }}
    GROUP BY indicator, geolocation, level_of_education, sex
    HAVING COUNT(*) > 1
)
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW completion_rate_prepared AS
WITH unpivoted AS (
    SELECT
        indicator, geolocation, level_of_education, sex,
        year, TRIM(raw_value) AS raw_value
    FROM {{ source('bronze', 'completion_rate') }}
    LATERAL VIEW STACK(
        5,
        2021, c_2021,
        2022, c_2022,
        2023, c_2023,
        2024, c_2024,
        2025, c_2025
    ) years AS year, raw_value
), labels AS (
    SELECT *,
        UPPER(TRIM(REGEXP_REPLACE(
            REGEXP_REPLACE(TRIM(geolocation), '^[.]+', ''),
            '[ ]+[0-9]+/[ ]*$', ''
        ))) AS mapping_label
    FROM unpivoted
)
SELECT *,
    REGEXP_REPLACE(mapping_label, '[^A-Z0-9]', '') AS alias_key,
    CASE
        WHEN mapping_label = 'PHILIPPINES' THEN 'PHL'
        WHEN mapping_label IN ('MIMAROPA', 'MIMAROPA REGION') THEN 'IVB'
        WHEN mapping_label RLIKE '^REGION [IVX]+[ -]?[AB]?$'
            THEN REGEXP_REPLACE(
                REGEXP_REPLACE(mapping_label, '^REGION ', ''),
                '[^A-Z0-9]', ''
            )
        WHEN mapping_label RLIKE '[(](NCR|CAR|BARMM|NIR)[)]$'
            THEN REGEXP_EXTRACT(
                mapping_label, '[(](NCR|CAR|BARMM|NIR)[)]$', 1
            )
    END AS code_hint,
    raw_value IS NULL OR raw_value IN ('', '..', '...') AS is_missing,
    TRY_CAST(raw_value AS DECIMAL(6,3)) AS parsed_rate
FROM labels
-- pondolens:statement --
-- Case/punctuation variants may agree on the same mapping.
-- Prefer an active exact alias, followed by an active code match.
-- Missing observations may retain a known region outside its alias period;
-- numeric observations must have a mapping applicable to their year.
CREATE OR REPLACE TEMP VIEW completion_rate_mapping_candidates AS
WITH crosswalk AS (
    SELECT DISTINCT
        REGEXP_REPLACE(UPPER(TRIM(source_region)), '[^A-Z0-9]', '') AS alias_key,
        UPPER(TRIM(region_code)) AS region_code,
        MAX(TRIM(region_name)) OVER (PARTITION BY UPPER(TRIM(region_code))) AS region_name,
        valid_from_year,
        valid_to_year,
        LOWER(TRIM(geographic_level)) AS geographic_level
    FROM {{ ref('shared_region_crosswalk') }}
    WHERE NULLIF(TRIM(source_region), '') IS NOT NULL
      AND NULLIF(TRIM(region_code), '') IS NOT NULL
      AND NULLIF(TRIM(region_name), '') IS NOT NULL
      AND (valid_from_year IS NULL OR valid_to_year IS NULL
           OR valid_from_year <= valid_to_year)
), candidates AS (
    SELECT p.*,
        c.region_code,
        c.region_name,
        CASE
            WHEN p.year BETWEEN COALESCE(c.valid_from_year, 1900)
                            AND COALESCE(c.valid_to_year, 9999)
                THEN CASE WHEN p.alias_key = c.alias_key THEN 1 ELSE 2 END
            ELSE CASE WHEN p.alias_key = c.alias_key THEN 3 ELSE 4 END
        END AS match_priority
    FROM completion_rate_prepared AS p
    LEFT JOIN crosswalk AS c
        ON (p.alias_key = c.alias_key OR p.code_hint = c.region_code)
       AND (c.region_code = 'PHL' OR c.geographic_level = 'region'
            OR (c.geographic_level IS NULL
                AND c.region_code NOT IN ('CO', 'NW')))
       AND (
           p.year BETWEEN COALESCE(c.valid_from_year, 1900)
                      AND COALESCE(c.valid_to_year, 9999)
           OR p.is_missing
       )
)
SELECT *,
    DENSE_RANK() OVER (
        PARTITION BY indicator, geolocation, level_of_education, sex, year
        ORDER BY match_priority
    ) AS match_rank
FROM candidates
-- pondolens:statement --
-- Do not choose arbitrarily between conflicting best matches.
SELECT assert_true(
    COUNT(*) = 0,
    'Ambiguous completion rate mapping: review crosswalk codes/names.'
)
FROM (
    SELECT indicator, geolocation, level_of_education, sex, year
    FROM completion_rate_mapping_candidates
    WHERE match_rank = 1 AND region_code IS NOT NULL
    GROUP BY indicator, geolocation, level_of_education, sex, year
    HAVING COUNT(DISTINCT STRUCT(region_code, region_name)) > 1
)
-- pondolens:statement --
-- Collapse only equivalent mapping candidates, not duplicate source records.
CREATE OR REPLACE TEMP VIEW completion_rate_silver_stage AS
SELECT DISTINCT
    year,
    region_code,
    region_name,
    CASE
        WHEN region_code = 'PHL' THEN 'national'
        WHEN region_code IS NOT NULL THEN 'region'
    END AS geographic_level,
    TRIM(REGEXP_REPLACE(indicator, '[ ]+[0-9]+/[ ]*$', '')) AS indicator,
    TRIM(REGEXP_REPLACE(
        level_of_education, '[ ]+[0-9]+/[ ]*$', ''
    )) AS level_of_education,
    TRIM(sex) AS sex,
    parsed_rate AS completion_rate,
    'percent' AS unit,
    raw_value,
    CASE
        WHEN raw_value IS NULL OR raw_value = '' THEN 'missing_blank'
        WHEN raw_value = '..' THEN 'source_marker_two_dots'
        WHEN raw_value = '...' THEN 'source_marker_three_dots'
        WHEN parsed_rate IS NULL THEN 'invalid_numeric'
        WHEN parsed_rate < 0 OR parsed_rate > 100 THEN 'invalid_range'
        ELSE 'available'
    END AS value_status
FROM completion_rate_mapping_candidates
WHERE match_rank = 1
-- pondolens:statement --
-- Mapping must preserve every source observation exactly once.
SELECT assert_true(
    (SELECT COUNT(*) FROM completion_rate_silver_stage)
        = (SELECT COUNT(*) FROM completion_rate_prepared),
    'Region mapping changed the completion rate observation count.'
)
-- pondolens:statement --
-- Validate source data before writing.
SELECT assert_true(
    COUNT(*) > 0
    AND COUNT_IF(
        NULLIF(TRIM(region_code), '') IS NULL
        OR NULLIF(TRIM(region_name), '') IS NULL
        OR NULLIF(TRIM(indicator), '') IS NULL
        OR level_of_education IS NULL
        OR level_of_education NOT IN (
            'Elementary',
            'Secondary (Junior High School)',
            'Secondary (Senior High School)'
        )
        OR sex IS NULL
        OR sex NOT IN ('Both Sexes', 'Female', 'Male')
        OR value_status IN ('invalid_numeric', 'invalid_range')
    ) = 0,
    'Load blocked: empty source, invalid values, or unmapped regions.'
)
FROM completion_rate_silver_stage
-- pondolens:statement --
SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate natural keys in completion rate source.'
)
FROM (
    SELECT
        indicator,
        year,
        region_code,
        level_of_education,
        sex
    FROM completion_rate_silver_stage
    GROUP BY
        indicator, year, region_code, level_of_education, sex
    HAVING COUNT(*) > 1
)
-- pondolens:statement --
-- Create the target when absent.
CREATE TABLE IF NOT EXISTS {{ this }} (
    completion_rate_id BIGINT,
    year INT,
    region_code STRING,
    region_name STRING,
    geographic_level STRING,
    indicator STRING,
    level_of_education STRING,
    sex STRING,
    completion_rate DECIMAL(6, 3),
    unit STRING,
    raw_value STRING,
    value_status STRING,
    processed_at TIMESTAMP
)
USING DELTA
-- pondolens:statement --
-- Support an existing table without the ID column.
DECLARE OR REPLACE VARIABLE completion_rate_ddl STRING
-- pondolens:statement --
SET VAR completion_rate_ddl = (
    SELECT CASE
        WHEN COUNT(*) = 0 THEN
            'ALTER TABLE {{ this }}
             ADD COLUMNS (completion_rate_id BIGINT)'
        ELSE
            'SELECT assert_true(true)'
    END
    FROM {{ this.database }}.information_schema.columns
    WHERE table_catalog = '{{ this.database }}'
      AND table_schema = '{{ this.schema }}'
      AND table_name = 'completion_rate'
      AND column_name = 'completion_rate_id'
)
-- pondolens:statement --
EXECUTE IMMEDIATE completion_rate_ddl
-- pondolens:statement --
-- Enable metadata-only column removal.
ALTER TABLE {{ this }}
SET TBLPROPERTIES (
    'delta.columnMapping.mode' = 'name'
)
-- pondolens:statement --
-- Remove only the lineage columns from earlier script versions.
-- On subsequent runs, this becomes a no-op.
SET VAR completion_rate_ddl = (
    SELECT CASE
        WHEN COUNT(*) = 0 THEN
            'SELECT assert_true(true)'
        ELSE CONCAT(
            'ALTER TABLE {{ this }} DROP COLUMNS (',
            CONCAT_WS(
                ', ',
                SORT_ARRAY(
                    COLLECT_LIST(CONCAT('`', column_name, '`'))
                )
            ),
            ')'
        )
    END
    FROM {{ this.database }}.information_schema.columns
    WHERE table_catalog = '{{ this.database }}'
      AND table_schema = '{{ this.schema }}'
      AND table_name = 'completion_rate'
      AND column_name IN (
          'source_indicator',
          'source_geolocation',
          'source_level_of_education',
          'source_drive_file_id',
          'source_file',
          'source_content_hash',
          'source_ingestion_run_id',
          'source_ingested_at'
      )
)
-- pondolens:statement --
EXECUTE IMMEDIATE completion_rate_ddl
-- pondolens:statement --
-- Validate existing target keys and IDs.
SELECT assert_true(
    COUNT_IF(
        year IS NULL
        OR NULLIF(TRIM(region_code), '') IS NULL
        OR NULLIF(TRIM(indicator), '') IS NULL
        OR NULLIF(TRIM(level_of_education), '') IS NULL
        OR NULLIF(TRIM(sex), '') IS NULL
        OR completion_rate_id <= 8000000
    ) = 0,
    'Invalid natural key or existing ID in completion rate target.'
)
FROM {{ this }}
-- pondolens:statement --
SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate natural keys in completion rate target.'
)
FROM (
    SELECT
        indicator,
        year,
        region_code,
        level_of_education,
        sex
    FROM {{ this }}
    GROUP BY
        indicator, year, region_code, level_of_education, sex
    HAVING COUNT(*) > 1
)
-- pondolens:statement --
SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate completion_rate_id values.'
)
FROM (
    SELECT completion_rate_id
    FROM {{ this }}
    WHERE completion_rate_id IS NOT NULL
    GROUP BY completion_rate_id
    HAVING COUNT(*) > 1
)
-- pondolens:statement --
SELECT assert_true(
    COUNT(*) = 0,
    'Target rows without IDs are missing from the current source.'
)
FROM {{ this }} AS t
LEFT ANTI JOIN completion_rate_silver_stage AS s
    ON  t.indicator = s.indicator
    AND t.year = s.year
    AND t.region_code = s.region_code
    AND t.level_of_education = s.level_of_education
    AND t.sex = s.sex
WHERE t.completion_rate_id IS NULL
-- pondolens:statement --
-- Preserve matched IDs and allocate IDs to unassigned keys.
MERGE INTO {{ this }} AS target
USING (
    WITH maximum_id AS (
        SELECT
            COALESCE(
                MAX(completion_rate_id),
                CAST(8000000 AS BIGINT)
            ) AS last_id
        FROM {{ this }}
    ),
    matched AS (
        SELECT
            s.*,
            t.completion_rate_id AS existing_id
        FROM completion_rate_silver_stage AS s
        LEFT JOIN {{ this }} AS t
            ON  t.indicator = s.indicator
            AND t.year = s.year
            AND t.region_code = s.region_code
            AND t.level_of_education = s.level_of_education
            AND t.sex = s.sex
    )
    SELECT
        m.* EXCEPT (existing_id),
        COALESCE(
            m.existing_id,
            maximum_id.last_id + ROW_NUMBER() OVER (
                PARTITION BY m.existing_id IS NULL
                ORDER BY
                    m.year,
                    m.region_code,
                    m.indicator,
                    m.level_of_education,
                    m.sex
            )
        ) AS completion_rate_id,
        CURRENT_TIMESTAMP() AS processed_at
    FROM matched AS m
    CROSS JOIN maximum_id
) AS source
ON  target.indicator = source.indicator
AND target.year = source.year
AND target.region_code = source.region_code
AND target.level_of_education = source.level_of_education
AND target.sex = source.sex

WHEN MATCHED THEN UPDATE SET
    target.completion_rate_id = source.completion_rate_id,
    target.region_name = source.region_name,
    target.geographic_level = source.geographic_level,
    target.completion_rate = source.completion_rate,
    target.unit = source.unit,
    target.raw_value = source.raw_value,
    target.value_status = source.value_status,
    target.processed_at = source.processed_at

WHEN NOT MATCHED THEN INSERT (
    completion_rate_id,
    year,
    region_code,
    region_name,
    geographic_level,
    indicator,
    level_of_education,
    sex,
    completion_rate,
    unit,
    raw_value,
    value_status,
    processed_at
)
VALUES (
    source.completion_rate_id,
    source.year,
    source.region_code,
    source.region_name,
    source.geographic_level,
    source.indicator,
    source.level_of_education,
    source.sex,
    source.completion_rate,
    source.unit,
    source.raw_value,
    source.value_status,
    source.processed_at
)
