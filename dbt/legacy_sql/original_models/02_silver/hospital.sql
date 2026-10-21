-- Hospital Silver
-- IDs start at 7,000,001.
-- Grain: year, region_code, hospital_type.
-- Current validated source: Government hospitals, 2021–2024, 17 regions.
-- New years/types are accepted when source validation and crosswalk mapping pass.
-- Run the complete script in one SQL session; stop on the first error.
-- Keep Bronze and the crosswalk unchanged for the duration of the load.
-- Run after successful Bronze ingestion.
-- Configure job maximum concurrent runs = 1.

CREATE SCHEMA IF NOT EXISTS pondolens.dev_silver;

-- Normalize punctuation and spacing in crosswalk labels.
-- Preserve canonical names, codes, and validity years.
CREATE OR REPLACE TEMP VIEW hospital_region_aliases AS
WITH crosswalk AS (
    SELECT DISTINCT
        UPPER(TRIM(region_code)) AS region_code,
        TRIM(region_name) AS region_name,
        source_region,
        valid_from_year,
        valid_to_year
    FROM pondolens.dev_silver.shared_region_crosswalk
),
labels AS (
    SELECT
        region_code,
        region_name,
        valid_from_year,
        valid_to_year,
        source_region AS alias_label
    FROM crosswalk

    UNION ALL

    SELECT
        region_code,
        region_name,
        valid_from_year,
        valid_to_year,
        region_name AS alias_label
    FROM crosswalk

    UNION ALL

    -- Explicit alias used by the Hospital source.
    SELECT
        region_code,
        region_name,
        valid_from_year,
        valid_to_year,
        'NCR - National Capital Region' AS alias_label
    FROM crosswalk
    WHERE region_code = 'NCR'
)
SELECT DISTINCT
    REGEXP_REPLACE(
        UPPER(TRIM(alias_label)),
        '[^A-Z0-9]',
        ''
    ) AS alias_key,
    region_code,
    region_name,
    valid_from_year,
    valid_to_year
FROM labels
WHERE NULLIF(TRIM(alias_label), '') IS NOT NULL;

-- Preserve every Bronze record for validation.
CREATE OR REPLACE TEMP VIEW hospital_prepared AS
SELECT
    TRIM(year) AS raw_year,
    TRY_CAST(TRIM(year) AS INT) AS year,
    TRIM(region_name) AS source_region_name,

    REGEXP_REPLACE(
        UPPER(TRIM(region_name)),
        '[^A-Z0-9]',
        ''
    ) AS alias_key,

    CASE UPPER(TRIM(hospital_type))
        WHEN 'GOVERNMENT' THEN 'Government'
        WHEN 'PRIVATE' THEN 'Private'
        WHEN 'TOTAL' THEN 'Total'
        ELSE TRIM(hospital_type)
    END AS hospital_type,

    TRIM(regulated_hospital_count) AS raw_count,

    TRY_CAST(TRIM(regulated_hospital_count) AS INT)
        AS regulated_hospital_count,

    LOWER(TRIM(unit)) AS unit

FROM pondolens.dev_bronze.hospital;

-- Deduplicate identical mappings for each source year.
CREATE OR REPLACE TEMP VIEW hospital_region_map AS
SELECT DISTINCT
    h.year,
    h.alias_key,
    c.region_code,
    c.region_name
FROM (
    SELECT DISTINCT year, alias_key
    FROM hospital_prepared
) AS h
INNER JOIN hospital_region_aliases AS c
    ON  h.alias_key = c.alias_key
    AND h.year BETWEEN c.valid_from_year AND c.valid_to_year;

-- Reject ambiguous normalized aliases before joining source records.
SELECT assert_true(
    COUNT(*) = 0,
    'Hospital crosswalk has conflicting mappings for the same alias and year.'
)
FROM (
    SELECT
        year,
        alias_key
    FROM hospital_region_map
    GROUP BY year, alias_key
    HAVING COUNT(*) > 1
);

CREATE OR REPLACE TEMP VIEW hospital_silver_stage AS
SELECT
    h.raw_year,
    h.raw_count,
    h.source_region_name,
    h.year,
    m.region_code,
    m.region_name,
    h.hospital_type,
    h.regulated_hospital_count,
    h.unit
FROM hospital_prepared AS h
LEFT JOIN hospital_region_map AS m
    ON  h.year = m.year
    AND h.alias_key = m.alias_key;

-- Validate source values and geography.
SELECT assert_true(
    COUNT(*) > 0
    AND COUNT_IF(
        raw_year IS NULL
        OR NOT (raw_year RLIKE '^[0-9]{4}$')
        OR year IS NULL
        OR year NOT BETWEEN 1900 AND 9999

        OR NULLIF(TRIM(region_code), '') IS NULL
        OR NULLIF(TRIM(region_name), '') IS NULL

        OR hospital_type IS NULL
        OR hospital_type NOT IN ('Government', 'Private', 'Total')

        OR raw_count IS NULL
        OR NOT (raw_count RLIKE '^[0-9]+$')
        OR regulated_hospital_count IS NULL
        OR regulated_hospital_count < 0

        OR unit IS NULL
        OR unit <> 'hospitals'
    ) = 0,
    'Hospital load blocked: empty source, invalid values, or unmapped regions.'
)
FROM hospital_silver_stage;

SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate year, region, and hospital type in Hospital source.'
)
FROM (
    SELECT
        year,
        region_code,
        hospital_type
    FROM hospital_silver_stage
    GROUP BY year, region_code, hospital_type
    HAVING COUNT(*) > 1
);

-- Create the permanent Silver table.
CREATE TABLE IF NOT EXISTS pondolens.dev_silver.hospital (
    hospital_id BIGINT,
    year INT,
    region_code STRING,
    region_name STRING,
    hospital_type STRING,
    regulated_hospital_count INT,
    unit STRING,
    processed_at TIMESTAMP
)
USING DELTA;

-- Validate existing IDs and natural keys.
SELECT assert_true(
    COUNT_IF(
        hospital_id IS NULL
        OR hospital_id <= 7000000
        OR year IS NULL
        OR year NOT BETWEEN 1900 AND 9999
        OR NULLIF(TRIM(region_code), '') IS NULL
        OR hospital_type IS NULL
        OR hospital_type NOT IN ('Government', 'Private', 'Total')
    ) = 0,
    'Invalid existing Hospital ID or natural key.'
)
FROM pondolens.dev_silver.hospital;

SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate natural keys in Hospital target.'
)
FROM (
    SELECT year, region_code, hospital_type
    FROM pondolens.dev_silver.hospital
    GROUP BY year, region_code, hospital_type
    HAVING COUNT(*) > 1
);

SELECT assert_true(
    COUNT(*) = 0,
    'Duplicate hospital_id values in target.'
)
FROM (
    SELECT hospital_id
    FROM pondolens.dev_silver.hospital
    GROUP BY hospital_id
    HAVING COUNT(*) > 1
);

-- Preserve existing IDs and allocate subsequent IDs to new keys.
MERGE INTO pondolens.dev_silver.hospital AS target
USING (
    WITH maximum_id AS (
        SELECT
            COALESCE(
                CAST(MAX(hospital_id) AS BIGINT),
                CAST(7000000 AS BIGINT)
            ) AS last_id
        FROM pondolens.dev_silver.hospital
    ),
    matched AS (
        SELECT
            s.year,
            s.region_code,
            s.region_name,
            s.hospital_type,
            s.regulated_hospital_count,
            s.unit,
            t.hospital_id AS existing_id
        FROM hospital_silver_stage AS s
        LEFT JOIN pondolens.dev_silver.hospital AS t
            ON  t.year = s.year
            AND t.region_code = s.region_code
            AND t.hospital_type = s.hospital_type
    )
    SELECT
        COALESCE(
            CAST(m.existing_id AS BIGINT),
            maximum_id.last_id + ROW_NUMBER() OVER (
                PARTITION BY m.existing_id IS NULL
                ORDER BY m.year, m.region_code, m.hospital_type
            )
        ) AS hospital_id,
        m.year,
        m.region_code,
        m.region_name,
        m.hospital_type,
        m.regulated_hospital_count,
        m.unit,
        CURRENT_TIMESTAMP() AS processed_at
    FROM matched AS m
    CROSS JOIN maximum_id
) AS source

ON  target.year = source.year
AND target.region_code = source.region_code
AND target.hospital_type = source.hospital_type

WHEN MATCHED AND (
    NOT (target.region_name <=> source.region_name)
    OR NOT (
        target.regulated_hospital_count
            <=> source.regulated_hospital_count
    )
    OR NOT (target.unit <=> source.unit)
    OR target.processed_at IS NULL
)
THEN UPDATE SET
    target.region_name = source.region_name,
    target.regulated_hospital_count = source.regulated_hospital_count,
    target.unit = source.unit,
    target.processed_at = source.processed_at

WHEN NOT MATCHED THEN INSERT (
    hospital_id,
    year,
    region_code,
    region_name,
    hospital_type,
    regulated_hospital_count,
    unit,
    processed_at
)
VALUES (
    source.hospital_id,
    source.year,
    source.region_code,
    source.region_name,
    source.hospital_type,
    source.regulated_hospital_count,
    source.unit,
    source.processed_at
);

-- Verify that every staged record matches the target.
SELECT assert_true(
    COUNT(*) = 0,
    'Hospital verification failed: staged records are missing or different.'
)
FROM hospital_silver_stage AS s
LEFT JOIN pondolens.dev_silver.hospital AS t
    ON  s.year = t.year
    AND s.region_code = t.region_code
    AND s.hospital_type = t.hospital_type
WHERE t.hospital_id IS NULL
   OR NOT (t.region_name <=> s.region_name)
   OR NOT (
       t.regulated_hospital_count
           <=> s.regulated_hospital_count
   )
   OR NOT (t.unit <=> s.unit);

-- Verify target ID and natural-key uniqueness after the merge.
SELECT assert_true(
    COUNT(*) = COUNT(DISTINCT hospital_id)
    AND COUNT(*) = COUNT(DISTINCT STRUCT(year, region_code, hospital_type))
    AND COUNT_IF(hospital_id IS NULL OR hospital_id <= 7000000) = 0,
    'Hospital verification failed: invalid or duplicate IDs or natural keys.'
)
FROM pondolens.dev_silver.hospital;

-- Final quality summary.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT hospital_id) AS unique_ids,
    MIN(hospital_id) AS first_id,
    MAX(hospital_id) AS last_id,
    MIN(year) AS first_year,
    MAX(year) AS last_year,
    COUNT(DISTINCT region_code) AS location_count,
    COUNT_IF(
        NULLIF(TRIM(region_code), '') IS NULL
        OR NULLIF(TRIM(region_name), '') IS NULL
    ) AS unmapped_rows,
    COUNT_IF(regulated_hospital_count IS NULL) AS missing_counts,
    COUNT_IF(regulated_hospital_count < 0) AS negative_counts
FROM pondolens.dev_silver.hospital;

