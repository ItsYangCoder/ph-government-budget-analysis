-- DIM_PARTICULAR (Gold)
-- Sources : pondolens.dev_silver.regional_appropriations, pondolens.dev_silver.regional_obligations
-- Target  : pondolens.dev_gold.dim_particular (materialized view, single object)
-- Grain   : one row per category + particular. fact_regional_budget joins on particular_id.
-- IDs     : 30000 = UNKNOWN (for fact rows with no match). Real particulars start at 30001. Max 39999.
--           Ordered by the first year a pair appears, then category and particular, so a new year's
--           particulars are added at the end and existing IDs stay the same.
-- Refresh : REFRESH MATERIALIZED VIEW pondolens.dev_gold.dim_particular;
--           Refresh this BEFORE fact_regional_budget, so the fact picks up the same IDs.
-- Requires: Unity Catalog, serverless or Pro SQL warehouse.

CREATE OR REPLACE MATERIALIZED VIEW pondolens.dev_gold.dim_particular (
    particular_id INT NOT NULL COMMENT 'Surrogate key. 30000 = UNKNOWN, 30001-39999 = particulars',
    category STRING NOT NULL COMMENT 'DEPARTMENTS, SPECIAL PURPOSE FUNDS, AUTOMATIC APPROPRIATIONS, UNKNOWN',
    particular STRING NOT NULL COMMENT 'Standard agency or fund name, uppercase',
    CONSTRAINT valid_particular_id EXPECT (particular_id BETWEEN 30000 AND 39999) ON VIOLATION FAIL UPDATE,
    CONSTRAINT has_names EXPECT (NULLIF(TRIM(category), '') IS NOT NULL AND NULLIF(TRIM(particular), '') IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Gold particular dimension. Business key: category, particular. Names standardized across GAA and obligations.'
AS
WITH particular_map AS (
    -- Same office or fund under different names across years. Uppercase on both sides.
    -- fact_regional_budget must apply the same list before looking up particular_id.
    SELECT * FROM VALUES
        ('THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE', 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'),
        ('PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE', 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'),
        ('OFFICE OF THE PRESS SECRETARY', 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'),
        ('DEBT SERVICE FUND-INTEREST PAYMENT', 'DEBT INTEREST PAYMENTS')
    AS m(source_particular, standard_particular)
),
source_pairs AS (
    SELECT
        year,
        UPPER(REGEXP_REPLACE(TRIM(category), r'\s+', ' ')) AS category,
        UPPER(REGEXP_REPLACE(TRIM(particular), r'\s+', ' ')) AS particular
    FROM pondolens.dev_silver.regional_appropriations

    UNION ALL

    SELECT
        year,
        UPPER(REGEXP_REPLACE(TRIM(category), r'\s+', ' ')) AS category,
        UPPER(REGEXP_REPLACE(TRIM(particular), r'\s+', ' ')) AS particular
    FROM pondolens.dev_silver.regional_obligations
),
pairs AS (
    SELECT
        s.category,
        COALESCE(m.standard_particular, s.particular) AS particular,
        MIN(s.year) AS first_year
    FROM source_pairs AS s
    LEFT JOIN particular_map AS m
        ON s.particular = m.source_particular
    WHERE NULLIF(s.category, '') IS NOT NULL
      AND NULLIF(s.particular, '') IS NOT NULL
      AND s.particular <> 'ALL'
      AND s.category NOT IN ('GRAND TOTAL', 'UNKNOWN')
    GROUP BY s.category, COALESCE(m.standard_particular, s.particular)
)
SELECT
    CAST(30000 AS INT) AS particular_id,
    'UNKNOWN' AS category,
    'UNKNOWN' AS particular

UNION ALL

SELECT
    CAST(30000 + ROW_NUMBER() OVER (ORDER BY first_year, category, particular) AS INT) AS particular_id,
    category,
    particular
FROM pairs;


-- CHECKS (run after create or refresh). Each stops with its own message.

-- 1. Unique IDs, unique pairs, UNKNOWN row present.
SELECT ASSERT_TRUE(
    COUNT(*) > 1
    AND COUNT(*) = COUNT(DISTINCT particular_id)
    AND COUNT(*) = COUNT(DISTINCT category, particular)
    AND COUNT_IF(particular_id = 30000 AND particular = 'UNKNOWN') = 1,
    'dim_particular is empty, has duplicate IDs or pairs, or is missing the UNKNOWN row.'
)
FROM pondolens.dev_gold.dim_particular;

-- 2. Every Silver pair has an ID (after the same name standardization).
WITH particular_map AS (
    SELECT * FROM VALUES
        ('THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE', 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'),
        ('PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE', 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'),
        ('OFFICE OF THE PRESS SECRETARY', 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'),
        ('DEBT SERVICE FUND-INTEREST PAYMENT', 'DEBT INTEREST PAYMENTS')
    AS m(source_particular, standard_particular)
),
source_pairs AS (
    SELECT UPPER(TRIM(category)) AS category, UPPER(TRIM(particular)) AS particular
    FROM pondolens.dev_silver.regional_appropriations
    UNION
    SELECT UPPER(TRIM(category)), UPPER(TRIM(particular))
    FROM pondolens.dev_silver.regional_obligations
)
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'A Silver category/particular has no ID in dim_particular.'
)
FROM source_pairs AS s
LEFT JOIN particular_map AS m
    ON s.particular = m.source_particular
LEFT ANTI JOIN pondolens.dev_gold.dim_particular AS d
    ON s.category = d.category
    AND COALESCE(m.standard_particular, s.particular) = d.particular
WHERE s.particular <> 'ALL';

-- 3. Review: names that look like the same agency spelled differently.
-- Expected: no rows. If rows appear, add the spellings to particular_map and recreate the view.
SELECT
    category,
    REGEXP_REPLACE(REGEXP_REPLACE(particular, r'\s*\([^)]*\)', ''), r'[^A-Z0-9]', '') AS name_key,
    CONCAT_WS(' | ', ARRAY_SORT(COLLECT_SET(particular))) AS spellings,
    COUNT(*) AS variations
FROM pondolens.dev_gold.dim_particular
GROUP BY 1, 2
HAVING COUNT(*) > 1;

-- 4. Result
SELECT *
FROM pondolens.dev_gold.dim_particular
ORDER BY particular_id;
