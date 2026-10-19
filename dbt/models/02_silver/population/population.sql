CREATE SCHEMA IF NOT EXISTS pondolens.dev_silver;
-- Run with max 1 concurrent job; do not run manually while the job is running.

CREATE TABLE IF NOT EXISTS pondolens.dev_silver.population (
    population_id INT NOT NULL,
    region_code STRING,
    region_name STRING,
    age_group STRING,
    age_min INT,
    age_max INT,
    sex STRING,
    year INT,
    population BIGINT,
    _processed_at TIMESTAMP,
    CONSTRAINT population_pk PRIMARY KEY (population_id)
)
USING DELTA;

-- Get distinct uppercase region codes and names from the crosswalk.
CREATE OR REPLACE TEMP VIEW population_region_map AS
SELECT DISTINCT
    UPPER(TRIM(region_code)) AS region_code,
    UPPER(TRIM(region_name)) AS region_name
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL;

-- Each region code must have one region name.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'A region code has multiple names in shared_region_crosswalk.'
)
FROM (
    SELECT region_code
    FROM population_region_map
    GROUP BY region_code
    HAVING COUNT(*) > 1
) AS conflicting_names;

-- Include MIMAROPA and MIMAROPA REGION as accepted source names.
CREATE OR REPLACE TEMP VIEW population_region_aliases AS
WITH region_variants AS (
    SELECT
        region_code,
        region_name,

        CASE
            WHEN REGEXP_REPLACE(
                UPPER(region_code), r'[^A-Z0-9]', ''
            ) = 'IVB'
              OR REGEXP_REPLACE(
                UPPER(region_name), r'[^A-Z0-9]', ''
            ) IN ('MIMAROPA', 'MIMAROPAREGION')
            THEN 'IVB'
            ELSE region_code
        END AS alias_code,

        EXPLODE(
            CASE
                WHEN REGEXP_REPLACE(
                    UPPER(region_code), r'[^A-Z0-9]', ''
                ) = 'IVB'
                  OR REGEXP_REPLACE(
                    UPPER(region_name), r'[^A-Z0-9]', ''
                ) IN ('MIMAROPA', 'MIMAROPAREGION')
                THEN ARRAY(
                    region_name,
                    'MIMAROPA',
                    'MIMAROPA REGION'
                )
                ELSE ARRAY(region_name)
            END
        ) AS alias_name
    FROM population_region_map
),

aliases AS (
    SELECT
        region_code,
        region_name,

        EXPLODE(ARRAY(
            region_code,
            alias_code,
            alias_name,
            CONCAT('REGION ', alias_code),
            CONCAT('REGION ', alias_code, ' ', alias_name),
            CONCAT(alias_code, ' ', alias_name),
            CONCAT(alias_name, ' ', alias_code),
            CONCAT(alias_name, ' REGION ', alias_code)
        )) AS region_alias
    FROM region_variants
)

SELECT DISTINCT
    REGEXP_REPLACE(
        UPPER(region_alias), r'[^A-Z0-9]', ''
    ) AS region_key,
    region_code,
    region_name
FROM aliases;

-- Each normalized label must match only one region.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'A region alias matches multiple regions. Review shared_region_crosswalk.'
)
FROM (
    SELECT region_key
    FROM population_region_aliases
    GROUP BY region_key
    HAVING COUNT(*) > 1
) AS conflicting_aliases;

-- Clean text and numbers; keep the latest ingestion for each Bronze key.
CREATE OR REPLACE TEMP VIEW population_bronze_clean AS
WITH trimmed AS (
    SELECT
        CASE
            WHEN LOWER(TRIM(region_name)) IN ('', 'null', '-', '–', '—')
                THEN NULL
            ELSE TRIM(region_name)
        END AS region_txt,

        CASE
            WHEN LOWER(TRIM(age_group)) IN ('', 'null', '-', '–', '—')
                THEN NULL
            ELSE TRIM(age_group)
        END AS age_group_txt,

        CASE
            WHEN LOWER(TRIM(sex)) IN ('', 'null', '-', '–', '—')
                THEN NULL
            ELSE TRIM(sex)
        END AS sex_txt,

        CASE
            WHEN LOWER(TRIM(year)) IN ('', 'null', '-', '–', '—')
                THEN NULL
            ELSE REPLACE(TRIM(year), ',', '')
        END AS year_txt,

        CASE
            WHEN LOWER(TRIM(age_min)) IN ('', 'null', '-', '–', '—')
                THEN NULL
            ELSE REPLACE(TRIM(age_min), ',', '')
        END AS age_min_txt,

        CASE
            WHEN LOWER(TRIM(age_max)) IN ('', 'null', '-', '–', '—')
                THEN NULL
            ELSE REPLACE(TRIM(age_max), ',', '')
        END AS age_max_txt,

        CASE
            WHEN LOWER(TRIM(population)) IN ('', 'null', '-', '–', '—')
                THEN NULL
            ELSE REPLACE(TRIM(population), ',', '')
        END AS population_txt,

        _run_id,
        _ingested_at,
        _source_modified_at
    FROM pondolens.dev_bronze.population
),

typed AS (
    SELECT
        *,

        NULLIF(
            REGEXP_REPLACE(UPPER(region_txt), r'[^A-Z0-9]', ''),
            ''
        ) AS region_key,

        CASE
            WHEN UPPER(age_group_txt) = 'TOTAL'
                THEN 'Total'
            WHEN UPPER(age_group_txt) = '85 AND OVER'
                THEN '85 and over'
            ELSE REGEXP_REPLACE(age_group_txt, r'\s*-\s*', ' - ')
        END AS age_group,

        INITCAP(sex_txt) AS sex,
        TRY_CAST(year_txt AS DECIMAL(38, 10)) AS year_d,
        TRY_CAST(age_min_txt AS DECIMAL(38, 10)) AS age_min_d,
        TRY_CAST(age_max_txt AS DECIMAL(38, 10)) AS age_max_d,
        TRY_CAST(population_txt AS DECIMAL(38, 10)) AS population_d
    FROM trimmed
),

ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY region_key, year_d, age_group, sex
            ORDER BY
                _ingested_at DESC,
                _source_modified_at DESC,
                _run_id DESC
        ) AS rn
    FROM typed
)

SELECT
    region_key,
    age_group,
    TRY_CAST(age_min_d AS INT) AS age_min,
    TRY_CAST(age_max_d AS INT) AS age_max,
    sex,
    TRY_CAST(year_d AS INT) AS year,
    TRY_CAST(population_d AS BIGINT) AS population,

    -- Flag values that cannot be read as whole numbers.
    (
        year_txt IS NOT NULL
        AND (year_d IS NULL OR year_d <> FLOOR(year_d) OR TRY_CAST(year_d AS INT) IS NULL)
    )
    OR (
        age_min_txt IS NOT NULL
        AND (age_min_d IS NULL OR age_min_d <> FLOOR(age_min_d) OR TRY_CAST(age_min_d AS INT) IS NULL)
    )
    OR (
        age_max_txt IS NOT NULL
        AND (age_max_d IS NULL OR age_max_d <> FLOOR(age_max_d) OR TRY_CAST(age_max_d AS INT) IS NULL)
    )
    OR (
        population_txt IS NOT NULL
        AND (
            population_d IS NULL
            OR population_d <> FLOOR(population_d)
            OR TRY_CAST(population_d AS BIGINT) IS NULL
        )
    ) AS has_invalid_number
FROM ranked
WHERE rn = 1;

-- List Bronze rows that cannot be loaded and their reasons.
CREATE OR REPLACE TEMP VIEW population_rejected AS
SELECT *
FROM (
    SELECT
        c.region_key,
        c.age_group,
        c.sex,
        c.year,
        c.population,

        CONCAT_WS(
            '; ',

            CASE
                WHEN c.region_key IS NULL THEN 'missing region'
                WHEN m.region_code IS NULL THEN 'unmapped region'
            END,

            CASE
                WHEN c.year IS NULL THEN 'missing year'
            END,

            CASE
                WHEN c.has_invalid_number THEN 'invalid number'
            END,

            CASE WHEN c.population < 0 THEN 'negative population' END,
            CASE
                WHEN c.age_group = '85 and over'
                     AND (c.age_min IS NULL OR c.age_min <> 85 OR c.age_max IS NOT NULL)
                    THEN 'invalid open-ended age limits'
                WHEN c.age_group NOT IN ('Total', '85 and over')
                     AND (c.age_min IS NULL OR c.age_max IS NULL
                          OR c.age_min <> TRY_CAST(SPLIT_PART(c.age_group, ' - ', 1) AS INT)
                          OR c.age_max <> TRY_CAST(SPLIT_PART(c.age_group, ' - ', 2) AS INT))
                    THEN 'age limits do not match age group'
            END,

            CASE
                WHEN c.sex IS NULL
                  OR c.sex NOT IN ('Both', 'Male', 'Female')
                THEN 'unexpected sex'
            END,

            CASE
                WHEN c.age_group IS NULL
                  OR c.age_group NOT IN (
                    'Total',
                    '0 - 4',
                    '5 - 9',
                    '10 - 14',
                    '15 - 19',
                    '20 - 24',
                    '25 - 29',
                    '30 - 34',
                    '35 - 39',
                    '40 - 44',
                    '45 - 49',
                    '50 - 54',
                    '55 - 59',
                    '60 - 64',
                    '65 - 69',
                    '70 - 74',
                    '75 - 79',
                    '80 - 84',
                    '85 and over'
                  )
                THEN 'unexpected age_group'
            END
        ) AS rejection_reason
    FROM population_bronze_clean AS c
    LEFT JOIN population_region_aliases AS m
        ON c.region_key = m.region_key
) AS rejected
WHERE rejection_reason <> '';

-- To inspect rejected rows: SELECT * FROM population_rejected.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Rejected Bronze rows found (bad region, year, number, sex or age group). See population_rejected.'
)
FROM population_rejected;

-- Keep 2021–2025, Both sexes and age groups; exclude the national total.
CREATE OR REPLACE TEMP VIEW population_stage AS
SELECT
    m.region_code,
    m.region_name,
    c.age_group,
    c.age_min,
    c.age_max,
    c.sex,
    c.year,
    c.population
FROM population_bronze_clean AS c
INNER JOIN population_region_aliases AS m
    ON c.region_key = m.region_key
WHERE m.region_code <> 'PHL'
  AND c.sex = 'Both'
  AND c.age_group <> 'Total'
  AND c.year BETWEEN 2021 AND 2025;

SELECT ASSERT_TRUE(COUNT(*) > 0, 'Population stage is empty; check ingestion and scope.')
FROM population_stage;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate or invalid natural keys in population target.')
FROM (
    SELECT region_code, year, age_group
    FROM pondolens.dev_silver.population
    GROUP BY region_code, year, age_group
    HAVING COUNT(*) > 1 OR NULLIF(TRIM(region_code), '') IS NULL
        OR year IS NULL OR NULLIF(TRIM(age_group), '') IS NULL
) AS invalid_target_keys;

-- Stop if different Bronze labels produce the same Silver key.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Duplicate mapped region/year/age-group keys found in population_stage.'
)
FROM (
    SELECT region_code, year, age_group
    FROM population_stage
    GROUP BY region_code, year, age_group
    HAVING COUNT(*) > 1
) AS duplicate_stage_keys;

-- Check existing IDs before merging.
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT population_id)
    AND COUNT_IF(population_id < 6000000) = 0,
    'Duplicate IDs, or IDs below 6000000.'
)
FROM pondolens.dev_silver.population;

-- Stop if a Bronze year contains under 80% of its existing Silver rows.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'A Bronze year has under 80% of the Silver rows; possible partial load.'
)
FROM (
    SELECT t.year
    FROM pondolens.dev_silver.population AS t
    INNER JOIN (
        SELECT year, COUNT(*) AS n
        FROM population_stage
        GROUP BY year
    ) AS s
        ON t.year = s.year
    GROUP BY t.year, s.n
    HAVING s.n < 0.8 * COUNT(*)
) AS partial_loads;

CREATE OR REPLACE TEMP VIEW population_numbered AS
WITH new_records AS (
    -- Only new records receive a new ID.
    SELECT s.*
    FROM population_stage AS s
    LEFT ANTI JOIN pondolens.dev_silver.population AS t
        ON s.region_code = t.region_code
        AND s.year = t.year
        AND s.age_group = t.age_group
),

last_id AS (
    -- Start at 6000000, or continue from the highest existing ID.
    SELECT
        COALESCE(
            MAX(CAST(population_id AS BIGINT)),
            5999999
        ) AS last_number
    FROM pondolens.dev_silver.population
)

SELECT
    s.*,
    l.last_number
        + ROW_NUMBER() OVER (
            ORDER BY
                s.year,
                s.region_code,
                COALESCE(s.age_min, -1),
                s.age_group
        ) AS next_id
FROM new_records AS s
CROSS JOIN last_id AS l;

SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'New IDs must be between 6000000 and 2147483647.'
)
FROM population_numbered
WHERE next_id NOT BETWEEN 6000000 AND 2147483647;

CREATE OR REPLACE TEMP VIEW population_merge_source AS

-- Existing records keep their IDs.
SELECT
    t.population_id,
    s.region_code,
    s.region_name,
    s.age_group,
    s.age_min,
    s.age_max,
    s.sex,
    s.year,
    s.population
FROM population_stage AS s
INNER JOIN pondolens.dev_silver.population AS t
    ON s.region_code = t.region_code
    AND s.year = t.year
    AND s.age_group = t.age_group

UNION ALL

SELECT
    CAST(next_id AS INT),
    region_code,
    region_name,
    age_group,
    age_min,
    age_max,
    sex,
    year,
    population
FROM population_numbered
;

MERGE INTO pondolens.dev_silver.population AS t
USING population_merge_source AS s
ON t.population_id = s.population_id

WHEN MATCHED AND NOT (
    t.region_name <=> s.region_name
    AND t.age_min <=> s.age_min
    AND t.age_max <=> s.age_max
    AND t.population <=> s.population
    AND t.sex <=> s.sex
)
THEN UPDATE SET
    t.region_name = s.region_name,
    t.age_min = s.age_min,
    t.age_max = s.age_max,
    t.population = s.population,
    t.sex = s.sex,
    t._processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED
THEN INSERT (
    population_id,
    region_code,
    region_name,
    age_group,
    age_min,
    age_max,
    sex,
    year,
    population,
    _processed_at
)
VALUES (
    s.population_id,
    s.region_code,
    s.region_name,
    s.age_group,
    s.age_min,
    s.age_max,
    s.sex,
    s.year,
    s.population,
    CURRENT_TIMESTAMP()
);