{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- ============================================================
-- PondoLens | Gold: fact_regional_expenditure
-- Author: Christine Joy D. Balansay
--
-- Grain: year × location × particular
-- Amounts: PHP; no additional multiplier
-- Fact IDs: start at 60001; preserve existing IDs
--
-- OFFICE OF THE PRESS SECRETARY → PCO, particular_id 30033.
-- Retired 30051 rows require a separate migration before this model runs.
--
-- Run all statements in order, in one session.
-- One writer only; keep Silver/dimensions unchanged during run.
-- Stop on any error.
-- ============================================================

-- RESULT 1
SET TIME ZONE 'UTC'
-- pondolens:statement --
-- ============================================================
-- 1. NAME NORMALIZATION
-- ============================================================

-- RESULT 2
CREATE OR REPLACE TEMP VIEW fre_particular_map AS
SELECT *
FROM VALUES
    (
        'THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE',
        'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
    ),
    (
        'PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE',
        'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
    ),
    (
        'OFFICE OF THE PRESS SECRETARY',
        'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
    ),
    (
        'DEBT SERVICE FUND-INTEREST PAYMENT',
        'DEBT INTEREST PAYMENTS'
    )
AS m(source_particular, standard_particular)
-- pondolens:statement --
-- ============================================================
-- 2. NORMALIZE SILVER SOURCES
-- ============================================================

-- RESULT 3
CREATE OR REPLACE TEMP VIEW fre_appropriations AS
SELECT
    s.gaa_id,
    s.year,
    UPPER(TRIM(s.region_code)) AS region_code,
    UPPER(REGEXP_REPLACE(TRIM(s.category), r'\s+', ' '))
        AS category,
    COALESCE(
        m.standard_particular,
        UPPER(REGEXP_REPLACE(TRIM(s.particular), r'\s+', ' '))
    ) AS particular,
    CAST(s.appropriation_amount AS DECIMAL(20, 4))
        AS appropriation_amount,
    CASE
        WHEN s.appropriation_amount IS NULL THEN 'SOURCE_NULL'
        WHEN s.appropriation_amount = 0 THEN 'REPORTED_ZERO'
        ELSE 'REPORTED'
    END AS appropriation_value_status
FROM {{ ref('regional_appropriations') }} s
LEFT JOIN fre_particular_map m
    ON UPPER(REGEXP_REPLACE(TRIM(s.particular), r'\s+', ' '))
        = m.source_particular
-- pondolens:statement --
-- RESULT 4
CREATE OR REPLACE TEMP VIEW fre_obligations AS
SELECT
    s.obligation_id,
    s.year,
    UPPER(TRIM(s.region_code)) AS region_code,
    UPPER(REGEXP_REPLACE(TRIM(s.category), r'\s+', ' '))
        AS category,
    COALESCE(
        m.standard_particular,
        UPPER(REGEXP_REPLACE(TRIM(s.particular), r'\s+', ' '))
    ) AS particular,
    CAST(s.expenditure_amount AS DECIMAL(20, 4))
        AS source_amount,
    LOWER(TRIM(s.value_status)) AS source_status,
    CASE
        WHEN LOWER(TRIM(s.value_status)) = 'numeric'
            THEN CAST(s.expenditure_amount AS DECIMAL(20, 4))
        ELSE CAST(NULL AS DECIMAL(20, 4))
    END AS obligation_amount,
    CASE
        WHEN LOWER(TRIM(s.value_status)) = 'numeric'
             AND s.expenditure_amount = 0
            THEN 'REPORTED_ZERO'
        WHEN LOWER(TRIM(s.value_status)) = 'numeric'
            THEN 'REPORTED'
        WHEN LOWER(TRIM(s.value_status)) = 'dash'
            THEN 'SOURCE_DASH'
        WHEN LOWER(TRIM(s.value_status)) = 'blank'
            THEN 'SOURCE_BLANK'
        ELSE 'INVALID_SOURCE_STATUS'
    END AS obligation_value_status
FROM {{ ref('regional_obligations') }} s
LEFT JOIN fre_particular_map m
    ON UPPER(REGEXP_REPLACE(TRIM(s.particular), r'\s+', ' '))
        = m.source_particular
-- pondolens:statement --
-- ============================================================
-- 3. VALIDATE SOURCE DATA
-- ============================================================

-- RESULT 5
SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT gaa_id)
    AND COUNT_IF(
        gaa_id IS NULL
        OR year IS NULL OR year NOT BETWEEN 2021 AND 2025
        OR region_code IS NULL OR region_code = ''
        OR category IS NULL OR category = ''
        OR particular IS NULL OR particular = ''
        OR category IN ('GRAND TOTAL', 'UNKNOWN')
        OR particular IN ('ALL', 'TOTAL', 'GRAND TOTAL', 'UNKNOWN')
        OR region_code IN ('TOTAL', 'GRAND TOTAL')
        OR appropriation_amount < 0
    ) = 0,
    'STOP: Invalid appropriation source records.'
)
FROM fre_appropriations
-- pondolens:statement --
-- RESULT 6
SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT obligation_id)
    AND COUNT_IF(
        obligation_id IS NULL
        OR year IS NULL OR year NOT BETWEEN 2021 AND 2025
        OR region_code IS NULL OR region_code = ''
        OR category IS NULL OR category = ''
        OR particular IS NULL OR particular = ''
        OR category IN ('GRAND TOTAL', 'UNKNOWN')
        OR particular IN ('ALL', 'TOTAL', 'GRAND TOTAL', 'UNKNOWN')
        OR region_code IN ('TOTAL', 'GRAND TOTAL')
        OR source_status IS NULL
        OR source_status NOT IN ('numeric', 'dash', 'blank')
        OR source_amount < 0
        OR (
            source_status = 'numeric'
            AND source_amount IS NULL
        )
        OR (
            source_status IN ('dash', 'blank')
            AND source_amount IS NOT NULL
            AND source_amount <> 0
        )
    ) = 0,
    'STOP: Invalid obligation source records or statuses.'
)
FROM fre_obligations
-- pondolens:statement --
-- RESULT 7
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate source keys after canonical mapping.'
)
FROM (
    SELECT
        'appropriations' AS dataset,
        year,
        region_code,
        category,
        particular
    FROM fre_appropriations
    GROUP BY year, region_code, category, particular
    HAVING COUNT(*) > 1

    UNION ALL

    SELECT
        'obligations' AS dataset,
        year,
        region_code,
        category,
        particular
    FROM fre_obligations
    GROUP BY year, region_code, category, particular
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 4. VALIDATE DIMENSIONS
-- ============================================================

-- RESULT 8
SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT location_id)
    AND COUNT(*) = COUNT(DISTINCT UPPER(TRIM(location_code)))
    AND COUNT_IF(
        location_id IS NULL
        OR location_code IS NULL
        OR TRIM(location_code) = ''
    ) = 0,
    'STOP: Invalid location dimension.'
)
FROM {{ ref('dim_location') }}
-- pondolens:statement --
-- RESULT 9
SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT year_id)
    AND COUNT(*) = COUNT(DISTINCT year)
    AND COUNT_IF(year_id IS NULL OR year IS NULL) = 0,
    'STOP: Invalid year dimension.'
)
FROM {{ ref('dim_year') }}
-- pondolens:statement --
-- RESULT 10
SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT particular_id)
    AND COUNT_IF(
        particular_id IS NULL
        OR category IS NULL OR TRIM(category) = ''
        OR particular IS NULL OR TRIM(particular) = ''
    ) = 0
    AND COUNT_IF(
        particular_id = 30033
        AND category = 'DEPARTMENTS'
        AND particular = 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
    ) = 1,
    'STOP: Invalid particular dimension or canonical PCO ID.'
)
FROM {{ ref('dim_particular') }}
-- pondolens:statement --
-- RESULT 11
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate normalized dimension definitions.'
)
FROM (
    SELECT
        UPPER(REGEXP_REPLACE(TRIM(category), r'\s+', ' ')),
        UPPER(REGEXP_REPLACE(TRIM(particular), r'\s+', ' '))
    FROM {{ ref('dim_particular') }}
    GROUP BY
        UPPER(REGEXP_REPLACE(TRIM(category), r'\s+', ' ')),
        UPPER(REGEXP_REPLACE(TRIM(particular), r'\s+', ' '))
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 5. COMBINE APPROPRIATIONS AND OBLIGATIONS
-- ============================================================

-- RESULT 12
CREATE OR REPLACE TEMP VIEW fre_combined AS
SELECT
    COALESCE(a.year, o.year) AS year,
    COALESCE(a.region_code, o.region_code) AS region_code,
    COALESCE(a.category, o.category) AS category,
    COALESCE(a.particular, o.particular) AS particular,
    a.gaa_id,
    o.obligation_id,
    a.appropriation_amount,
    CASE
        WHEN a.gaa_id IS NULL THEN 'NOT_IN_SOURCE'
        ELSE a.appropriation_value_status
    END AS appropriation_value_status,
    o.obligation_amount,
    CASE
        WHEN o.obligation_id IS NULL THEN 'NOT_IN_SOURCE'
        ELSE o.obligation_value_status
    END AS obligation_value_status
FROM fre_appropriations a
FULL OUTER JOIN fre_obligations o
    ON a.year = o.year
   AND a.region_code = o.region_code
   AND a.category = o.category
   AND a.particular = o.particular
-- pondolens:statement --
-- RESULT 13
SELECT ASSERT_TRUE(
    COUNT(gaa_id) = (SELECT COUNT(*) FROM fre_appropriations)
    AND COUNT(obligation_id) = (
        SELECT COUNT(*) FROM fre_obligations
    ),
    'STOP: Source combination lost or multiplied observations.'
)
FROM fre_combined
-- pondolens:statement --
-- ============================================================
-- 6. RESOLVE FOREIGN KEYS
-- ============================================================

-- RESULT 14
CREATE OR REPLACE TEMP VIEW fre_mapped AS
SELECT
    y.year_id,
    l.location_id,
    d.particular_id,
    s.appropriation_amount,
    s.appropriation_value_status,
    s.obligation_amount,
    s.obligation_value_status,
    s.year,
    s.region_code,
    s.category,
    s.particular
FROM fre_combined s
LEFT JOIN {{ ref('dim_year') }} y
    ON s.year = y.year
LEFT JOIN {{ ref('dim_location') }} l
    ON s.region_code = UPPER(TRIM(l.location_code))
LEFT JOIN {{ ref('dim_particular') }} d
    ON s.category =
        UPPER(REGEXP_REPLACE(TRIM(d.category), r'\s+', ' '))
   AND s.particular =
        UPPER(REGEXP_REPLACE(TRIM(d.particular), r'\s+', ' '))
-- pondolens:statement --
-- RESULT 15
-- Expected: NO ROWS.
SELECT
    year,
    region_code,
    category,
    particular,
    year_id,
    location_id,
    particular_id
FROM fre_mapped
WHERE year_id IS NULL
   OR location_id IS NULL
   OR particular_id IS NULL
   OR particular_id IN (30000, 30051)
-- pondolens:statement --
-- RESULT 16
SELECT ASSERT_TRUE(
    COUNT(*) = (SELECT COUNT(*) FROM fre_combined)
    AND COUNT_IF(
        year_id IS NULL
        OR location_id IS NULL
        OR particular_id IS NULL
        OR particular_id IN (30000, 30051)
    ) = 0,
    'STOP: Missing dimension matches or multiplied joins.'
)
FROM fre_mapped
-- pondolens:statement --
-- RESULT 17
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate mapped business keys.'
)
FROM (
    SELECT year_id, location_id, particular_id
    FROM fre_mapped
    GROUP BY year_id, location_id, particular_id
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 7. CREATE AND VALIDATE TARGET
-- ============================================================

-- RESULT 18
CREATE TABLE IF NOT EXISTS
{{ this }} (
    regional_expenditure_id BIGINT NOT NULL,
    year_id INT NOT NULL,
    location_id INT NOT NULL,
    particular_id INT NOT NULL,
    appropriation_amount DECIMAL(20, 4),
    appropriation_value_status STRING NOT NULL,
    obligation_amount DECIMAL(20, 4),
    obligation_value_status STRING NOT NULL,
    processed_at TIMESTAMP NOT NULL
)
USING DELTA
COMMENT 'Appropriations and obligations in PHP using canonical particular IDs.'
-- pondolens:statement --
-- RESULT 19
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT regional_expenditure_id)
    AND COUNT_IF(
        regional_expenditure_id IS NULL
        OR regional_expenditure_id < 60001
        OR year_id IS NULL
        OR location_id IS NULL
        OR particular_id IS NULL
    ) = 0,
    'STOP: Invalid existing fact identifiers.'
)
FROM {{ this }}
-- pondolens:statement --
-- RESULT 20
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate existing fact business keys.'
)
FROM (
    SELECT year_id, location_id, particular_id
    FROM {{ this }}
    GROUP BY year_id, location_id, particular_id
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 8. VALIDATE EXISTING CANONICAL KEYS
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Retired particular 30051 requires a separate migration.'
)
FROM {{ this }}
WHERE particular_id = 30051
-- pondolens:statement --
-- RESULT 22
-- General source omissions are not automatically deleted.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Unexpected target keys absent from the current source.'
)
FROM {{ this }} t
LEFT ANTI JOIN fre_mapped s
    ON t.year_id = s.year_id
   AND t.location_id = s.location_id
   AND t.particular_id = s.particular_id
WHERE t.particular_id <> 30051
-- pondolens:statement --
-- ============================================================
-- 9. ALLOCATE IDs ONLY FOR NEW CANONICAL KEYS
-- ============================================================

-- RESULT 25
CREATE OR REPLACE TEMP VIEW fre_new_ids AS
SELECT
    s.year_id,
    s.location_id,
    s.particular_id,
    m.max_id + ROW_NUMBER() OVER (
        ORDER BY s.year_id, s.location_id, s.particular_id
    ) AS regional_expenditure_id
FROM (
    SELECT s.*
    FROM fre_mapped s
    LEFT ANTI JOIN {{ this }} t
        ON s.year_id = t.year_id
       AND s.location_id = t.location_id
       AND s.particular_id = t.particular_id
) s
CROSS JOIN (
    SELECT COALESCE(
        MAX(regional_expenditure_id),
        CAST(60000 AS BIGINT)
    ) AS max_id
    FROM {{ this }}
) m
-- pondolens:statement --
-- RESULT 26
CREATE OR REPLACE TEMP VIEW fre_upsert AS
SELECT
    COALESCE(
        t.regional_expenditure_id,
        n.regional_expenditure_id
    ) AS regional_expenditure_id,
    s.year_id,
    s.location_id,
    s.particular_id,
    s.appropriation_amount,
    s.appropriation_value_status,
    s.obligation_amount,
    s.obligation_value_status
FROM fre_mapped s
LEFT JOIN {{ this }} t
    ON s.year_id = t.year_id
   AND s.location_id = t.location_id
   AND s.particular_id = t.particular_id
LEFT JOIN fre_new_ids n
    ON s.year_id = n.year_id
   AND s.location_id = n.location_id
   AND s.particular_id = n.particular_id
-- pondolens:statement --
-- ============================================================
-- 10. UPSERT CANONICAL RECORDS
-- Existing IDs are retained; source omissions are not deleted.
-- ============================================================

-- RESULT 28: MERGE METRICS
MERGE INTO {{ this }} t
USING fre_upsert s
ON  t.year_id = s.year_id
AND t.location_id = s.location_id
AND t.particular_id = s.particular_id

WHEN MATCHED AND (
       NOT (t.appropriation_amount <=> s.appropriation_amount)
    OR NOT (
        t.appropriation_value_status
        <=> s.appropriation_value_status
    )
    OR NOT (t.obligation_amount <=> s.obligation_amount)
    OR NOT (
        t.obligation_value_status
        <=> s.obligation_value_status
    )
 )
THEN UPDATE SET
    t.appropriation_amount = s.appropriation_amount,
    t.appropriation_value_status = s.appropriation_value_status,
    t.obligation_amount = s.obligation_amount,
    t.obligation_value_status = s.obligation_value_status,
    t.processed_at = CURRENT_TIMESTAMP()

WHEN NOT MATCHED
THEN INSERT (
    regional_expenditure_id,
    year_id,
    location_id,
    particular_id,
    appropriation_amount,
    appropriation_value_status,
    obligation_amount,
    obligation_value_status,
    processed_at
)
VALUES (
    s.regional_expenditure_id,
    s.year_id,
    s.location_id,
    s.particular_id,
    s.appropriation_amount,
    s.appropriation_value_status,
    s.obligation_amount,
    s.obligation_value_status,
    CURRENT_TIMESTAMP()
)
-- pondolens:statement --
-- ============================================================
-- 11. POST-LOAD VALIDATION
-- ============================================================

-- RESULT 29
SELECT ASSERT_TRUE(
    COUNT(*) = (SELECT COUNT(*) FROM fre_mapped)
    AND COUNT(*) = COUNT(DISTINCT regional_expenditure_id)
    AND COUNT_IF(particular_id = 30051) = 0,
    'STOP: Unexpected final count, duplicate IDs, or legacy references.'
)
FROM {{ this }}
-- pondolens:statement --
-- RESULT 30
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate final business keys.'
)
FROM (
    SELECT year_id, location_id, particular_id
    FROM {{ this }}
    GROUP BY year_id, location_id, particular_id
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- RESULT 31
SELECT ASSERT_TRUE(
    COUNT(*) = (SELECT COUNT(*) FROM fre_mapped)
    AND COUNT_IF(
        t.regional_expenditure_id IS NULL
        OR NOT (t.appropriation_amount <=> s.appropriation_amount)
        OR NOT (
            t.appropriation_value_status
            <=> s.appropriation_value_status
        )
        OR NOT (t.obligation_amount <=> s.obligation_amount)
        OR NOT (
            t.obligation_value_status
            <=> s.obligation_value_status
        )
        OR t.processed_at IS NULL
    ) = 0,
    'STOP: Saved observations differ from the canonical source.'
)
FROM fre_mapped s
LEFT JOIN {{ this }} t
    ON s.year_id = t.year_id
   AND s.location_id = t.location_id
   AND s.particular_id = t.particular_id
-- pondolens:statement --
-- RESULT 32
SELECT ASSERT_TRUE(
    (
        SUM(appropriation_amount) <=> (
            SELECT SUM(appropriation_amount)
            FROM fre_appropriations
        )
    )
    AND (
        SUM(obligation_amount) <=> (
            SELECT SUM(obligation_amount)
            FROM fre_obligations
        )
    )
    AND COUNT(appropriation_amount) = (
        SELECT COUNT(appropriation_amount)
        FROM fre_appropriations
    )
    AND COUNT(obligation_amount) = (
        SELECT COUNT(obligation_amount)
        FROM fre_obligations
    ),
    'STOP: Financial totals or populated counts differ from Silver.'
)
FROM {{ this }}
-- pondolens:statement --
-- ============================================================
-- 12. FINAL RESULTS
-- ============================================================

-- RESULT 33: OUTPUT A — OVERALL SUMMARY
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT regional_expenditure_id) AS unique_fact_ids,
    COUNT_IF(particular_id = 30051) AS legacy_press_rows,
    MIN(regional_expenditure_id) AS first_fact_id,
    MAX(regional_expenditure_id) AS last_fact_id,
    SUM(appropriation_amount) AS appropriation_php,
    SUM(obligation_amount) AS reported_obligation_php
FROM {{ this }}
-- pondolens:statement --
-- RESULT 34: OUTPUT B — CONSOLIDATED 2023 PCO
SELECT
    y.year,
    f.particular_id,
    COUNT(*) AS row_count,
    COUNT(f.appropriation_amount) AS populated_appropriations,
    SUM(f.appropriation_amount) AS appropriation_php,
    SUM(f.obligation_amount) AS obligation_php
FROM {{ this }} f
JOIN {{ ref('dim_year') }} y
    ON f.year_id = y.year_id
WHERE y.year = 2023
  AND f.particular_id = 30033
GROUP BY y.year, f.particular_id
-- pondolens:statement --
-- RESULT 35: OUTPUT C — YEAR / GEOGRAPHIC COVERAGE
SELECT
    y.year,
    l.geographic_level,
    COUNT(*) AS row_count,
    COUNT(f.appropriation_amount) AS populated_appropriations,
    COUNT(f.obligation_amount) AS populated_obligations,
    COUNT_IF(f.appropriation_amount IS NULL)
        AS missing_appropriations,
    COUNT_IF(f.obligation_amount IS NULL)
        AS missing_obligations,
    SUM(f.appropriation_amount) AS appropriation_php,
    SUM(f.obligation_amount) AS reported_obligation_php
FROM {{ this }} f
JOIN {{ ref('dim_year') }} y
    ON f.year_id = y.year_id
JOIN {{ ref('dim_location') }} l
    ON f.location_id = l.location_id
GROUP BY y.year, l.geographic_level
ORDER BY y.year, l.geographic_level
-- pondolens:statement --
-- RESULT 36: OUTPUT D — SOURCE STATUSES
SELECT
    appropriation_value_status,
    obligation_value_status,
    COUNT(*) AS row_count
FROM {{ this }}
GROUP BY appropriation_value_status, obligation_value_status
ORDER BY appropriation_value_status, obligation_value_status
