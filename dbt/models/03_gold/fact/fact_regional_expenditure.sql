-- ============================================================
-- PondoLens | Gold: fact_regional_expenditure
-- Author: Christine Joy D. Balansay
--
-- Grain: year × location × particular
-- Measures: appropriation and obligation, in PHP
-- Fact IDs: start at 60001; preserved on reruns
--
-- Source dash/blank → NULL amount with explicit status.
-- Missing counterpart → NULL amount with NOT_IN_SOURCE.
-- Press Secretary remains separate from PCO.
-- ============================================================

SET TIME ZONE 'UTC';


-- ============================================================
-- 1. SHARED NAME NORMALIZATION
-- Same aliases as dim_particular.
-- ============================================================

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
        'DEBT SERVICE FUND-INTEREST PAYMENT',
        'DEBT INTEREST PAYMENTS'
    )
AS m(source_particular, standard_particular);


-- ============================================================
-- 2. NORMALIZE SILVER SOURCES
-- No additional multiplication: Silver amounts are treated as PHP.
-- ============================================================

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

FROM pondolens.dev_silver.regional_appropriations s
LEFT JOIN fre_particular_map m
    ON UPPER(REGEXP_REPLACE(TRIM(s.particular), r'\s+', ' '))
        = m.source_particular;


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

FROM pondolens.dev_silver.regional_obligations s
LEFT JOIN fre_particular_map m
    ON UPPER(REGEXP_REPLACE(TRIM(s.particular), r'\s+', ' '))
        = m.source_particular;


-- ============================================================
-- 3. VALIDATE SOURCE RECORDS
-- Unexpected totals, missing keys, and unsupported statuses stop load.
-- ============================================================

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
    'STOP: Invalid appropriation IDs, keys, scope, totals, or amounts.'
)
FROM fre_appropriations;


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
        OR (source_status = 'numeric' AND source_amount IS NULL)
        OR (
            source_status IN ('dash', 'blank')
            AND source_amount IS NOT NULL
            AND source_amount <> 0
        )
    ) = 0,
    'STOP: Invalid obligation IDs, keys, scope, amounts, or source statuses.'
)
FROM fre_obligations;


-- Check uniqueness AFTER alias normalization.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate normalized source business keys.'
)
FROM (
    SELECT
        'appropriations' AS dataset,
        year, region_code, category, particular
    FROM fre_appropriations
    GROUP BY year, region_code, category, particular
    HAVING COUNT(*) > 1

    UNION ALL

    SELECT
        'obligations' AS dataset,
        year, region_code, category, particular
    FROM fre_obligations
    GROUP BY year, region_code, category, particular
    HAVING COUNT(*) > 1
) duplicates;


-- ============================================================
-- 4. VALIDATE DIMENSION UNIQUENESS
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT location_id)
    AND COUNT(*) = COUNT(DISTINCT UPPER(TRIM(location_code)))
    AND COUNT_IF(
        location_id IS NULL
        OR location_code IS NULL OR TRIM(location_code) = ''
    ) = 0,
    'STOP: Invalid or duplicate location keys.'
)
FROM pondolens.dev_gold.dim_location;


SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT year_id)
    AND COUNT(*) = COUNT(DISTINCT year)
    AND COUNT_IF(year_id IS NULL OR year IS NULL) = 0,
    'STOP: Invalid or duplicate year keys.'
)
FROM pondolens.dev_gold.dim_year;


SELECT ASSERT_TRUE(
    COUNT(*) > 0
    AND COUNT(*) = COUNT(DISTINCT particular_id)
    AND COUNT_IF(
        particular_id IS NULL
        OR category IS NULL OR TRIM(category) = ''
        OR particular IS NULL OR TRIM(particular) = ''
    ) = 0,
    'STOP: Invalid or duplicate particular IDs.'
)
FROM pondolens.dev_gold.dim_particular;


SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate normalized dimension definitions.'
)
FROM (
    SELECT
        UPPER(REGEXP_REPLACE(TRIM(category), r'\s+', ' ')),
        UPPER(REGEXP_REPLACE(TRIM(particular), r'\s+', ' '))
    FROM pondolens.dev_gold.dim_particular
    GROUP BY
        UPPER(REGEXP_REPLACE(TRIM(category), r'\s+', ' ')),
        UPPER(REGEXP_REPLACE(TRIM(particular), r'\s+', ' '))
    HAVING COUNT(*) > 1
) duplicates;


-- ============================================================
-- 5. COMBINE SOURCES AT THEIR SHARED BUSINESS GRAIN
-- FULL OUTER JOIN preserves unmatched source observations.
-- ============================================================

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
   AND a.particular = o.particular;


-- Confirm each source row survived exactly once.
SELECT ASSERT_TRUE(
    COUNT(gaa_id) = (SELECT COUNT(*) FROM fre_appropriations)
    AND COUNT(obligation_id) = (SELECT COUNT(*) FROM fre_obligations),
    'STOP: Source combination lost or multiplied records.'
)
FROM fre_combined;


-- ============================================================
-- 6. RESOLVE DIMENSION KEYS
-- ============================================================

CREATE OR REPLACE TEMP VIEW fre_mapped AS
SELECT
    y.year_id,
    l.location_id,
    d.particular_id,
    s.appropriation_amount,
    s.appropriation_value_status,
    s.obligation_amount,
    s.obligation_value_status,

    -- Diagnostic attributes
    s.year,
    s.region_code,
    s.category,
    s.particular

FROM fre_combined s

LEFT JOIN pondolens.dev_gold.dim_year y
    ON s.year = y.year

LEFT JOIN pondolens.dev_gold.dim_location l
    ON s.region_code = UPPER(TRIM(l.location_code))

LEFT JOIN pondolens.dev_gold.dim_particular d
    ON s.category =
        UPPER(REGEXP_REPLACE(TRIM(d.category), r'\s+', ' '))
   AND s.particular =
        UPPER(REGEXP_REPLACE(TRIM(d.particular), r'\s+', ' '));


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
   OR particular_id = 30000;


SELECT ASSERT_TRUE(
    COUNT_IF(
        year_id IS NULL
        OR location_id IS NULL
        OR particular_id IS NULL
        OR particular_id = 30000
    ) = 0
    AND COUNT(*) = (SELECT COUNT(*) FROM fre_combined),
    'STOP: Missing dimension matches or multiplied joins.'
)
FROM fre_mapped;


SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate mapped year/location/particular keys.'
)
FROM (
    SELECT year_id, location_id, particular_id
    FROM fre_mapped
    GROUP BY year_id, location_id, particular_id
    HAVING COUNT(*) > 1
) duplicates;


-- ============================================================
-- 7. CREATE PERSISTENT DELTA FACT
-- ============================================================

CREATE TABLE IF NOT EXISTS
pondolens.dev_gold.fact_regional_expenditure (
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
COMMENT 'Appropriations and obligations in PHP by year, location, and particular.';


-- ============================================================
-- 8. VALIDATE EXISTING TARGET BEFORE WRITING
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT regional_expenditure_id)
    AND COUNT_IF(
        regional_expenditure_id IS NULL
        OR regional_expenditure_id < 60001
        OR year_id IS NULL
        OR location_id IS NULL
        OR particular_id IS NULL
    ) = 0,
    'STOP: Invalid or duplicate existing fact identifiers.'
)
FROM pondolens.dev_gold.fact_regional_expenditure;


SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing fact contains duplicate business keys.'
)
FROM (
    SELECT year_id, location_id, particular_id
    FROM pondolens.dev_gold.fact_regional_expenditure
    GROUP BY year_id, location_id, particular_id
    HAVING COUNT(*) > 1
) duplicates;


-- ============================================================
-- 9. ALLOCATE IDs FOR NEW KEYS ONLY
-- Single writer required; preserve existing IDs.
-- ============================================================

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
    LEFT ANTI JOIN pondolens.dev_gold.fact_regional_expenditure t
        ON s.year_id = t.year_id
       AND s.location_id = t.location_id
       AND s.particular_id = t.particular_id
) s
CROSS JOIN (
    SELECT COALESCE(
        MAX(regional_expenditure_id),
        CAST(60000 AS BIGINT)
    ) AS max_id
    FROM pondolens.dev_gold.fact_regional_expenditure
) m;


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

LEFT JOIN pondolens.dev_gold.fact_regional_expenditure t
    ON s.year_id = t.year_id
   AND s.location_id = t.location_id
   AND s.particular_id = t.particular_id

LEFT JOIN fre_new_ids n
    ON s.year_id = n.year_id
   AND s.location_id = n.location_id
   AND s.particular_id = n.particular_id;


-- ============================================================
-- 10. PERSIST OBSERVATIONS
-- Unchanged records retain processed_at.
-- ============================================================

MERGE INTO pondolens.dev_gold.fact_regional_expenditure t
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

WHEN NOT MATCHED THEN INSERT (
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
);


-- ============================================================
-- 11. RECONCILE EVERY LOADED RECORD
-- Null-safe comparisons validate amounts and source statuses.
-- ============================================================

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
    'STOP: Persisted amounts/statuses do not match validated source.'
)
FROM fre_mapped s
LEFT JOIN pondolens.dev_gold.fact_regional_expenditure t
    ON s.year_id = t.year_id
   AND s.location_id = t.location_id
   AND s.particular_id = t.particular_id;


SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT regional_expenditure_id),
    'STOP: Duplicate persisted fact IDs.'
)
FROM pondolens.dev_gold.fact_regional_expenditure;


SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate persisted fact business keys.'
)
FROM (
    SELECT year_id, location_id, particular_id
    FROM pondolens.dev_gold.fact_regional_expenditure
    GROUP BY year_id, location_id, particular_id
    HAVING COUNT(*) > 1
) duplicates;


SELECT ASSERT_TRUE(
    COUNT_IF(
        y.year_id IS NULL
        OR l.location_id IS NULL
        OR d.particular_id IS NULL
        OR f.particular_id = 30000
        OR f.processed_at IS NULL
        OR f.appropriation_value_status IS NULL
        OR f.obligation_value_status IS NULL

        OR f.appropriation_value_status NOT IN (
            'REPORTED', 'REPORTED_ZERO',
            'SOURCE_NULL', 'NOT_IN_SOURCE'
        )

        OR f.obligation_value_status NOT IN (
            'REPORTED', 'REPORTED_ZERO',
            'SOURCE_DASH', 'SOURCE_BLANK', 'NOT_IN_SOURCE'
        )

        OR (
            f.appropriation_value_status = 'REPORTED'
            AND (
                f.appropriation_amount IS NULL
                OR f.appropriation_amount <= 0
            )
        )

        OR (
            f.obligation_value_status = 'REPORTED'
            AND (
                f.obligation_amount IS NULL
                OR f.obligation_amount <= 0
            )
        )

        OR (
            f.appropriation_value_status = 'REPORTED_ZERO'
            AND NOT (f.appropriation_amount <=> 0)
        )

        OR (
            f.obligation_value_status = 'REPORTED_ZERO'
            AND NOT (f.obligation_amount <=> 0)
        )

        OR (
            f.appropriation_value_status IN (
                'SOURCE_NULL', 'NOT_IN_SOURCE'
            )
            AND f.appropriation_amount IS NOT NULL
        )

        OR (
            f.obligation_value_status IN (
                'SOURCE_DASH', 'SOURCE_BLANK', 'NOT_IN_SOURCE'
            )
            AND f.obligation_amount IS NOT NULL
        )
    ) = 0,
    'STOP: Invalid saved foreign keys or amount/status combinations.'
)
FROM pondolens.dev_gold.fact_regional_expenditure f
LEFT JOIN pondolens.dev_gold.dim_year y
    ON f.year_id = y.year_id
LEFT JOIN pondolens.dev_gold.dim_location l
    ON f.location_id = l.location_id
LEFT JOIN pondolens.dev_gold.dim_particular d
    ON f.particular_id = d.particular_id;


-- ============================================================
-- 12. FINAL RESULTS
-- SUM ignores NULL; inspect missing counts with the totals.
-- ============================================================

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
FROM pondolens.dev_gold.fact_regional_expenditure f
JOIN pondolens.dev_gold.dim_year y
    ON f.year_id = y.year_id
JOIN pondolens.dev_gold.dim_location l
    ON f.location_id = l.location_id
GROUP BY y.year, l.geographic_level
ORDER BY y.year, l.geographic_level;


SELECT
    appropriation_value_status,
    obligation_value_status,
    COUNT(*) AS row_count
FROM pondolens.dev_gold.fact_regional_expenditure
GROUP BY appropriation_value_status, obligation_value_status
ORDER BY appropriation_value_status, obligation_value_status;


SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT regional_expenditure_id) AS unique_fact_ids,
    MIN(regional_expenditure_id) AS first_fact_id,
    MAX(regional_expenditure_id) AS last_fact_id
FROM pondolens.dev_gold.fact_regional_expenditure;