%sql
-- Run after ingestion finishes, in one session, with max 1 concurrent run.

CREATE TABLE IF NOT EXISTS pondolens.dev_silver.regional_appropriations (
    gaa_id INT NOT NULL,
    year INT,
    category STRING,
    particular STRING,
    region_code STRING,
    region_name STRING,
    appropriation_amount DECIMAL(20,2),
    processed_at TIMESTAMP,
    CONSTRAINT regional_appropriations_pk PRIMARY KEY (gaa_id)
)
USING DELTA;


-- 1. Read uppercase code/name pairs from the crosswalk.
CREATE OR REPLACE TEMP VIEW regional_gaa_region_map AS
SELECT DISTINCT
    NULLIF(UPPER(TRIM(region_code)), '') AS region_code,
    NULLIF(UPPER(TRIM(region_name)), '') AS region_name
FROM pondolens.dev_silver.shared_region_crosswalk;

SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(region_code)
    AND COUNT(*) = COUNT(region_name)
    AND COUNT(*) = COUNT(DISTINCT region_code)
    AND COUNT_IF(
        REGEXP_REPLACE(region_code, r'[^A-Z0-9]', '') = ''
    ) = 0
    AND COUNT_IF(
        REGEXP_REPLACE(region_name, r'[^A-Z0-9]', '') = ''
    ) = 0,
    'Crosswalk is empty, has missing values, or gives multiple names for one code.'
)
FROM regional_gaa_region_map;

CREATE OR REPLACE TEMP VIEW regional_gaa_region_aliases AS
WITH variants AS (
    SELECT
        region_code,
        region_name,

        CASE
            WHEN REGEXP_REPLACE(
                region_code, r'[^A-Z0-9]', ''
            ) = 'IVB'
              OR REGEXP_REPLACE(
                region_name, r'[^A-Z0-9]', ''
            ) IN ('MIMAROPA', 'MIMAROPAREGION')
            THEN 'IVB'
            ELSE region_code
        END AS alias_code,

        EXPLODE(
            CASE
                WHEN REGEXP_REPLACE(
                    region_code, r'[^A-Z0-9]', ''
                ) = 'IVB'
                  OR REGEXP_REPLACE(
                    region_name, r'[^A-Z0-9]', ''
                ) IN ('MIMAROPA', 'MIMAROPAREGION')
                THEN ARRAY(
                    region_name,
                    'MIMAROPA',
                    'MIMAROPA REGION'
                )
                ELSE ARRAY(region_name)
            END
        ) AS alias_name
    FROM regional_gaa_region_map
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
            CONCAT(alias_code, ' ', alias_name),
            CONCAT('REGION ', alias_code, ' ', alias_name),
            CONCAT(alias_name, ' ', alias_code),
            CONCAT(alias_name, ' REGION ', alias_code)
        )) AS region_alias
    FROM variants

    UNION ALL

    SELECT
        'NW',
        'NATIONWIDE',
        'NATIONWIDE'

    UNION ALL

    SELECT
        region_code,
        region_name,
        'CARAGA REGION'
    FROM regional_gaa_region_map
    WHERE region_code = 'XIII'
       OR region_name IN ('CARAGA', 'CARAGA REGION')
)
SELECT DISTINCT
    REGEXP_REPLACE(
        UPPER(region_alias), r'[^A-Z0-9]', ''
    ) AS region_key,
    region_code,
    region_name
FROM aliases;

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT region_key),
    'One normalized label matches multiple crosswalk entries.'
)
FROM regional_gaa_region_aliases;


-- 2. Clean source values and keep 2021–2025 detail records.
CREATE OR REPLACE TEMP VIEW regional_gaa_prepared AS
WITH cleaned AS (
    SELECT
        source_name,
        source_page,

        TRIM(CAST(year AS STRING)) AS year_text,
        TRY_CAST(
            TRIM(CAST(year AS STRING)) AS INT
        ) AS year,

        CASE
            WHEN LOWER(TRIM(category)) IN ('', 'null')
                THEN NULL
            ELSE UPPER(TRIM(category))
        END AS category,

        CASE
            WHEN LOWER(TRIM(particulars)) IN ('', 'null')
                THEN NULL
            ELSE UPPER(TRIM(particulars))
        END AS particular,

        regions AS source_region,

        NULLIF(
            REGEXP_REPLACE(
                UPPER(TRIM(regions)), r'[^A-Z0-9]', ''
            ),
            ''
        ) AS region_key,

        TRIM(
            CAST(expenditure_amount AS STRING)
        ) AS amount_text,

        REGEXP_REPLACE(
            UPPER(TRIM(unit_amount)), r'[^A-Z0-9]', ''
        ) AS unit_key,

        REGEXP_REPLACE(
            UPPER(TRIM(price_basis)), r'[^A-Z0-9]', ''
        ) AS basis_key,

        _ingested_at,
        TRY_CAST(
            _source_modified_at AS TIMESTAMP
        ) AS source_modified_at

    FROM pondolens.dev_bronze.regional_appropriation
),
typed AS (
    SELECT
        *,

        CASE
            WHEN amount_text IS NULL
              OR LOWER(amount_text) IN ('', 'null')
                THEN CAST(NULL AS DECIMAL(20,2))

            WHEN amount_text IN ('-', '–', '—')
                THEN CAST(0 AS DECIMAL(20,2))

            WHEN REPLACE(amount_text, ',', '')
                RLIKE r'^[+-]?[0-9]+([.][0-9]{1,2})?$'
                THEN TRY_CAST(
                    TRY_CAST(
                        REPLACE(amount_text, ',', '')
                        AS DECIMAL(23,2)
                    ) * CAST(1000 AS DECIMAL(4,0))
                    AS DECIMAL(20,2)
                )

            ELSE CAST(NULL AS DECIMAL(20,2))
        END AS appropriation_amount

    FROM cleaned
)
SELECT
    b.*,
    m.region_code,
    m.region_name
FROM typed b
LEFT JOIN regional_gaa_region_aliases m
    ON b.region_key = m.region_key
WHERE (
        b.year BETWEEN 2021 AND 2025
        OR b.year IS NULL
    )
  AND COALESCE(
        REGEXP_REPLACE(b.particular, r'[^A-Z0-9]', ''),
        ''
    ) <> 'ALL'
  AND COALESCE(b.region_key, '') <> 'TOTAL';


-- 3. Select the latest ingestion; reject invalid records and conflicting ties.
CREATE OR REPLACE TEMP VIEW regional_gaa_latest AS
SELECT *
FROM (
    SELECT
        *,

        DENSE_RANK() OVER (
            PARTITION BY
                year,
                category,
                particular,
                COALESCE(region_code, region_key)
            ORDER BY
                _ingested_at DESC NULLS LAST,
                source_modified_at DESC NULLS LAST
        ) AS latest_rank

    FROM regional_gaa_prepared
) ranked
WHERE latest_rank = 1;

CREATE OR REPLACE TEMP VIEW regional_gaa_rejected AS
SELECT *
FROM (
    SELECT
        *,

        CONCAT_WS(
            '; ',

            CASE
                WHEN year IS NULL
                THEN 'missing or invalid year'
            END,

            CASE
                WHEN category IS NULL
                THEN 'missing category'
            END,

            CASE
                WHEN particular IS NULL
                THEN 'missing particular'
            END,

            CASE
                WHEN region_code IS NULL
                THEN 'missing or unmapped region'
            END,

            CASE
                WHEN amount_text IS NOT NULL
                  AND LOWER(amount_text) NOT IN ('', 'null')
                  AND appropriation_amount IS NULL
                THEN 'invalid amount or amount overflow'
            END,

            CASE
                WHEN appropriation_amount < 0
                THEN 'negative amount'
            END,

            CASE
                WHEN unit_key IS NULL
                  OR unit_key NOT IN (
                      'THOUSANDPESOS',
                      'INTHOUSANDPESOS',
                      'THOUSANDPHILIPPINEPESOS',
                      'INTHOUSANDPHILIPPINEPESOS'
                  )
                THEN 'unit is not thousand pesos'
            END,

            CASE
                WHEN basis_key IS NULL
                  OR basis_key NOT IN ('GAA', 'GAAUPDATED')
                THEN 'basis is not GAA or GAA Updated'
            END,

            CASE
                WHEN _ingested_at IS NULL
                THEN 'missing ingestion timestamp'
            END

        ) AS rejection_reason

    FROM regional_gaa_latest
) checked
WHERE rejection_reason <> '';

SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Rejected source records found. Inspect regional_gaa_rejected.'
)
FROM regional_gaa_rejected;

CREATE OR REPLACE TEMP VIEW regional_gaa_stage AS
SELECT DISTINCT
    year,
    category,
    particular,
    region_code,
    region_name,
    appropriation_amount
FROM regional_gaa_latest;

SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(year)
    AND COUNT(*) = COUNT(category)
    AND COUNT(*) = COUNT(particular)
    AND COUNT(*) = COUNT(region_code)
    AND COUNT(*) = COUNT(region_name)
    AND COUNT(*) = COUNT(
        DISTINCT STRUCT(
            year, category, particular, region_code
        )
    ),
    'Empty stage, missing keys, or conflicting latest values for the same mapped key.'
)
FROM regional_gaa_stage;


-- 4. Normalize existing records while retaining their IDs.
CREATE OR REPLACE TEMP VIEW regional_gaa_target_clean AS
SELECT
    t.gaa_id,
    t.year,

    CASE
        WHEN LOWER(TRIM(t.category)) IN ('', 'null')
            THEN NULL
        ELSE UPPER(TRIM(t.category))
    END AS category,

    CASE
        WHEN LOWER(TRIM(t.particular)) IN ('', 'null')
            THEN NULL
        ELSE UPPER(TRIM(t.particular))
    END AS particular,

    COALESCE(c.region_code, n.region_code) AS region_code,
    COALESCE(c.region_name, n.region_name) AS region_name,

    t.appropriation_amount,

    (
        t.year IS NOT NULL
        AND t.year NOT BETWEEN 2021 AND 2025
    )
    OR COALESCE(
        REGEXP_REPLACE(
            UPPER(TRIM(t.particular)), r'[^A-Z0-9]', ''
        ),
        ''
    ) = 'ALL'
    OR COALESCE(
        REGEXP_REPLACE(
            UPPER(TRIM(t.region_code)), r'[^A-Z0-9]', ''
        ),
        ''
    ) = 'TOTAL'
    OR COALESCE(
        REGEXP_REPLACE(
            UPPER(TRIM(t.region_name)), r'[^A-Z0-9]', ''
        ),
        ''
    ) = 'TOTAL' AS excluded

FROM pondolens.dev_silver.regional_appropriations t

LEFT JOIN regional_gaa_region_aliases c
    ON REGEXP_REPLACE(
        UPPER(TRIM(t.region_code)), r'[^A-Z0-9]', ''
    ) = c.region_key

LEFT JOIN regional_gaa_region_aliases n
    ON REGEXP_REPLACE(
        UPPER(TRIM(t.region_name)), r'[^A-Z0-9]', ''
    ) = n.region_key;

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT gaa_id)
    AND COUNT_IF(
        gaa_id NOT BETWEEN 1000001 AND 2147483647
    ) = 0,
    'Existing IDs are missing, duplicated or outside the allowed range.'
)
FROM regional_gaa_target_clean;

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(year)
    AND COUNT(*) = COUNT(category)
    AND COUNT(*) = COUNT(particular)
    AND COUNT(*) = COUNT(region_code)
    AND COUNT(*) = COUNT(region_name)
    AND COUNT(*) = COUNT(
        DISTINCT STRUCT(
            year, category, particular, region_code
        )
    ),
    'Existing retained records have missing keys, unmapped regions or duplicate mapped keys.'
)
FROM regional_gaa_target_clean
WHERE NOT excluded;


-- 5. Assign IDs only to new keys.
CREATE OR REPLACE TEMP VIEW regional_gaa_numbered AS
WITH new_records AS (
    SELECT s.*
    FROM regional_gaa_stage s

    LEFT ANTI JOIN regional_gaa_target_clean t
        ON NOT t.excluded
        AND s.year = t.year
        AND s.category = t.category
        AND s.particular = t.particular
        AND s.region_code = t.region_code
),
last_id AS (
    SELECT
        COALESCE(
            MAX(CAST(gaa_id AS BIGINT)),
            1000000
        ) AS last_number
    FROM pondolens.dev_silver.regional_appropriations
)
SELECT
    s.*,

    l.last_number + ROW_NUMBER() OVER (
        ORDER BY
            s.year,
            s.category,
            s.particular,
            s.region_code
    ) AS next_id

FROM new_records s
CROSS JOIN last_id l;

SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'New gaa_id exceeds the INT range.'
)
FROM regional_gaa_numbered
WHERE next_id NOT BETWEEN 1000001 AND 2147483647;


-- 6. Insert or update records; preserve keys absent from this batch.
CREATE OR REPLACE TEMP VIEW regional_gaa_merge_source AS
SELECT
    t.gaa_id,
    t.year,
    t.category,
    t.particular,
    t.region_code,
    t.region_name,

    CASE
        WHEN s.year IS NOT NULL
            THEN s.appropriation_amount
        ELSE t.appropriation_amount
    END AS appropriation_amount,

    t.excluded AS removed

FROM regional_gaa_target_clean t

LEFT JOIN regional_gaa_stage s
    ON NOT t.excluded
    AND t.year = s.year
    AND t.category = s.category
    AND t.particular = s.particular
    AND t.region_code = s.region_code

UNION ALL

SELECT
    CAST(next_id AS INT),
    year,
    category,
    particular,
    region_code,
    region_name,
    appropriation_amount,
    FALSE AS removed

FROM regional_gaa_numbered;

MERGE INTO pondolens.dev_silver.regional_appropriations t
USING regional_gaa_merge_source s
ON t.gaa_id = s.gaa_id

WHEN MATCHED AND s.removed
THEN DELETE

WHEN MATCHED AND NOT s.removed AND NOT (
    t.category <=> s.category
    AND t.particular <=> s.particular
    AND t.region_code <=> s.region_code
    AND t.region_name <=> s.region_name
    AND t.appropriation_amount <=> s.appropriation_amount
)
THEN UPDATE SET
    t.category = s.category,
    t.particular = s.particular,
    t.region_code = s.region_code,
    t.region_name = s.region_name,
    t.appropriation_amount = s.appropriation_amount,
    t.processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED AND NOT s.removed
THEN INSERT (
    gaa_id,
    year,
    category,
    particular,
    region_code,
    region_name,
    appropriation_amount,
    processed_at
)
VALUES (
    s.gaa_id,
    s.year,
    s.category,
    s.particular,
    s.region_code,
    s.region_name,
    s.appropriation_amount,
    CURRENT_TIMESTAMP()
);