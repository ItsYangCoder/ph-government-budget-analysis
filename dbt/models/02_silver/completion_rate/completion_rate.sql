-- Completion Rate Silver
-- Scope: 2021–2025
-- IDs start at 8,000,001.
-- Requires complete Bronze ingestion and one concurrent writer.

CREATE SCHEMA IF NOT EXISTS pondolens.dev_silver;

-- Validate crosswalk uniqueness.
SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate region aliases in shared_region_crosswalk.'
)
FROM (
    SELECT UPPER(TRIM(source_region_name))
    FROM pondolens.dev_silver.shared_region_crosswalk
    GROUP BY UPPER(TRIM(source_region_name))
    HAVING COUNT(*) > 1
);

-- Transform Bronze into the Silver grain.
CREATE OR REPLACE TEMP VIEW completion_rate_silver_stage AS
WITH unpivoted AS (
    SELECT
        indicator,
        geolocation,
        level_of_education,
        sex,
        year,
        TRIM(raw_value) AS raw_value
    FROM pondolens.dev_bronze.completion_rate
    LATERAL VIEW STACK(
        5,
        2021, c_2021,
        2022, c_2022,
        2023, c_2023,
        2024, c_2024,
        2025, c_2025
    ) years AS year, raw_value
),
prepared AS (
    SELECT
        *,
        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(TRIM(geolocation), '^[.]+', ''),
                '[ ]+[0-9]+/[ ]*$',
                ''
            )
        ) AS mapping_label,
        TRY_CAST(raw_value AS DECIMAL(6, 3)) AS parsed_rate
    FROM unpivoted
)
SELECT
    p.year,
    c.region_code,
    c.region_name,
    CASE
        WHEN c.region_code = 'PHL' THEN 'national'
        WHEN c.region_code IS NOT NULL THEN 'region'
    END AS geographic_level,

    TRIM(
        REGEXP_REPLACE(p.indicator, '[ ]+[0-9]+/[ ]*$', '')
    ) AS indicator,

    TRIM(
        REGEXP_REPLACE(
            p.level_of_education,
            '[ ]+[0-9]+/[ ]*$',
            ''
        )
    ) AS level_of_education,

    TRIM(p.sex) AS sex,
    p.parsed_rate AS completion_rate,
    'percent' AS unit,
    p.raw_value,

    CASE
        WHEN p.raw_value IS NULL OR p.raw_value = ''
            THEN 'missing_blank'
        WHEN p.raw_value = '..'
            THEN 'source_marker_two_dots'
        WHEN p.raw_value = '...'
            THEN 'source_marker_three_dots'
        WHEN p.parsed_rate IS NULL
            THEN 'invalid_numeric'
        WHEN p.parsed_rate < 0 OR p.parsed_rate > 100
            THEN 'invalid_range'
        ELSE 'available'
    END AS value_status
FROM prepared AS p
LEFT JOIN pondolens.dev_silver.shared_region_crosswalk AS c
    ON UPPER(p.mapping_label)
        = UPPER(TRIM(c.source_region_name));

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
FROM completion_rate_silver_stage;

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
);

-- Create the target when absent.
CREATE TABLE IF NOT EXISTS pondolens.dev_silver.completion_rate (
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
USING DELTA;

-- Support an existing table without the ID column.
DECLARE OR REPLACE VARIABLE completion_rate_ddl STRING;

SET VAR completion_rate_ddl = (
    SELECT CASE
        WHEN COUNT(*) = 0 THEN
            'ALTER TABLE pondolens.dev_silver.completion_rate
             ADD COLUMNS (completion_rate_id BIGINT)'
        ELSE
            'SELECT assert_true(true)'
    END
    FROM pondolens.information_schema.columns
    WHERE table_catalog = 'pondolens'
      AND table_schema = 'dev_silver'
      AND table_name = 'completion_rate'
      AND column_name = 'completion_rate_id'
);

EXECUTE IMMEDIATE completion_rate_ddl;

-- Enable metadata-only column removal.
ALTER TABLE pondolens.dev_silver.completion_rate
SET TBLPROPERTIES (
    'delta.columnMapping.mode' = 'name'
);

-- Remove only the lineage columns from earlier script versions.
-- On subsequent runs, this becomes a no-op.
SET VAR completion_rate_ddl = (
    SELECT CASE
        WHEN COUNT(*) = 0 THEN
            'SELECT assert_true(true)'
        ELSE CONCAT(
            'ALTER TABLE pondolens.dev_silver.completion_rate DROP COLUMNS (',
            CONCAT_WS(
                ', ',
                SORT_ARRAY(
                    COLLECT_LIST(CONCAT('`', column_name, '`'))
                )
            ),
            ')'
        )
    END
    FROM pondolens.information_schema.columns
    WHERE table_catalog = 'pondolens'
      AND table_schema = 'dev_silver'
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
);

EXECUTE IMMEDIATE completion_rate_ddl;

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
FROM pondolens.dev_silver.completion_rate;

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
    FROM pondolens.dev_silver.completion_rate
    GROUP BY
        indicator, year, region_code, level_of_education, sex
    HAVING COUNT(*) > 1
);

SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate completion_rate_id values.'
)
FROM (
    SELECT completion_rate_id
    FROM pondolens.dev_silver.completion_rate
    WHERE completion_rate_id IS NOT NULL
    GROUP BY completion_rate_id
    HAVING COUNT(*) > 1
);

SELECT assert_true(
    COUNT(*) = 0,
    'Target rows without IDs are missing from the current source.'
)
FROM pondolens.dev_silver.completion_rate AS t
LEFT ANTI JOIN completion_rate_silver_stage AS s
    ON  t.indicator = s.indicator
    AND t.year = s.year
    AND t.region_code = s.region_code
    AND t.level_of_education = s.level_of_education
    AND t.sex = s.sex
WHERE t.completion_rate_id IS NULL;

-- Preserve matched IDs and allocate IDs to unassigned keys.
MERGE INTO pondolens.dev_silver.completion_rate AS target
USING (
    WITH maximum_id AS (
        SELECT
            COALESCE(
                MAX(completion_rate_id),
                CAST(8000000 AS BIGINT)
            ) AS last_id
        FROM pondolens.dev_silver.completion_rate
    ),
    matched AS (
        SELECT
            s.*,
            t.completion_rate_id AS existing_id
        FROM completion_rate_silver_stage AS s
        LEFT JOIN pondolens.dev_silver.completion_rate AS t
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

WHEN NOT MATCHED BY SOURCE
    AND target.year BETWEEN 2021 AND 2025
THEN DELETE;