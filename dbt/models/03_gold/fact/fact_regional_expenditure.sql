-- PondoLens | fact_regional_expenditure | Databricks SQL
-- See fact_regional_expenditure_documentation.md for assumptions and execution notes.
-- 4392 total rows, id starts at 60000

-- Step 2: Notebook code cell
SET TIME ZONE 'UTC';

-- Step 3: Notebook code cell
-- Apply the SAME four particular aliases as dim_particular; Silver retains original labels.
CREATE OR REPLACE TEMP VIEW gold_obligations_prepared AS
SELECT
    obligation_id,
    year,
    TRIM(category) AS category,
    CASE UPPER(TRIM(particular))
        WHEN 'THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
        WHEN 'PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
        WHEN 'OFFICE OF THE PRESS SECRETARY' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
        WHEN 'DEBT SERVICE FUND-INTEREST PAYMENT' THEN 'DEBT INTEREST PAYMENTS'
        ELSE UPPER(TRIM(particular))
    END AS particular,
    CASE UPPER(TRIM(region_name))
        WHEN 'BARMM' THEN 'BARMM'
        WHEN 'CARAGA' THEN 'XIII'
        WHEN 'CENTRAL OFFICE' THEN 'CO'
        WHEN 'CORDILLERA ADMINISTRATIVE REGION' THEN 'CAR'
        WHEN 'NATIONAL CAPITAL REGION' THEN 'NCR'
        WHEN 'NATIONWIDE' THEN 'NW'
        WHEN 'NEGROS ISLAND REGION' THEN 'NIR'
        WHEN 'REGION I' THEN 'I'
        WHEN 'REGION II' THEN 'II'
        WHEN 'REGION III' THEN 'III'
        WHEN 'REGION IVA' THEN 'IVA'
        WHEN 'REGION IVB' THEN 'IVB'
        WHEN 'REGION V' THEN 'V'
        WHEN 'REGION VI' THEN 'VI'
        WHEN 'REGION VII' THEN 'VII'
        WHEN 'REGION VIII' THEN 'VIII'
        WHEN 'REGION IX' THEN 'IX'
        WHEN 'REGION X' THEN 'X'
        WHEN 'REGION XI' THEN 'XI'
        WHEN 'REGION XII' THEN 'XII'
        WHEN 'BANGSAMORO AUTONOMOUS REGION IN MUSLIM MINDANAO' THEN 'BARMM'
        WHEN 'BICOL REGION' THEN 'V'
        WHEN 'CAGAYAN VALLEY' THEN 'II'
        WHEN 'CALABARZON' THEN 'IVA'
        WHEN 'CENTRAL LUZON' THEN 'III'
        WHEN 'CENTRAL VISAYAS' THEN 'VII'
        WHEN 'DAVAO REGION' THEN 'XI'
        WHEN 'EASTERN VISAYAS' THEN 'VIII'
        WHEN 'ILOCOS REGION' THEN 'I'
        WHEN 'MIMAROPA' THEN 'IVB'
        WHEN 'NORTHERN MINDANAO' THEN 'X'
        WHEN 'SOCCSKSARGEN' THEN 'XII'
        WHEN 'WESTERN VISAYAS' THEN 'VI'
        WHEN 'ZAMBOANGA PENINSULA' THEN 'IX'
        WHEN 'REGION IV-A' THEN 'IVA'
        WHEN 'REGION IV-B' THEN 'IVB'
    END AS region_code,
    expenditure_amount AS obligation_amount
FROM pondolens.dev_silver.regional_obligations
WHERE year BETWEEN 2021 AND 2025
  AND (
      region_name IS NULL
      OR UPPER(TRIM(region_name)) <> 'TOTAL'
  );

-- Step 4: Notebook code cell
CREATE OR REPLACE TEMP VIEW gold_appropriations_prepared AS
SELECT
    gaa_id,
    year,
    TRIM(category) AS category,
    CASE UPPER(TRIM(particular))
        WHEN 'THE PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
        WHEN 'PRESIDENTIAL COMMUNICATIONS OPERATIONS OFFICE' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
        WHEN 'OFFICE OF THE PRESS SECRETARY' THEN 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
        WHEN 'DEBT SERVICE FUND-INTEREST PAYMENT' THEN 'DEBT INTEREST PAYMENTS'
        ELSE UPPER(TRIM(particular))
    END AS particular,
    TRIM(region_code) AS region_code,
    appropriation_amount
FROM pondolens.dev_silver.regional_appropriations
WHERE year BETWEEN 2021 AND 2025;

-- Step 6: Notebook code cell
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Invalid appropriation fields.')
FROM gold_appropriations_prepared
WHERE year IS NULL OR NULLIF(TRIM(category), '') IS NULL
   OR NULLIF(TRIM(particular), '') IS NULL
   OR NULLIF(TRIM(region_code), '') IS NULL;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Invalid obligation fields or unmapped geography.')
FROM gold_obligations_prepared
WHERE year IS NULL OR NULLIF(TRIM(category), '') IS NULL
   OR NULLIF(TRIM(particular), '') IS NULL OR region_code IS NULL;

-- Step 8: Notebook code cell
CREATE OR REPLACE TEMP VIEW gold_appropriations_normalized AS
SELECT
    year,
    UPPER(TRIM(category)) AS category,
    UPPER(TRIM(particular)) AS particular,
    UPPER(TRIM(region_code)) AS region_code,
    appropriation_amount,
    1 AS source_present
FROM gold_appropriations_prepared
WHERE UPPER(TRIM(particular)) <> 'ALL'
  AND UPPER(TRIM(category)) <> 'GRAND TOTAL';

CREATE OR REPLACE TEMP VIEW gold_obligations_normalized AS
SELECT
    year,
    UPPER(TRIM(category)) AS category,
    UPPER(TRIM(particular)) AS particular,
    UPPER(TRIM(region_code)) AS region_code,
    obligation_amount,
    1 AS source_present
FROM gold_obligations_prepared
WHERE UPPER(TRIM(particular)) <> 'ALL'
  AND UPPER(TRIM(category)) <> 'GRAND TOTAL';

-- Stop if normalization produces duplicate source keys.
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate normalized source keys.')
FROM (
    SELECT 'APPROPRIATION' AS source,
           year, category, particular, region_code
    FROM gold_appropriations_normalized
    GROUP BY year, category, particular, region_code
    HAVING COUNT(*) > 1

    UNION ALL

    SELECT 'OBLIGATION',
           year, category, particular, region_code
    FROM gold_obligations_normalized
    GROUP BY year, category, particular, region_code
    HAVING COUNT(*) > 1
);

CREATE OR REPLACE TEMP VIEW gold_regional_expenditure_prepared AS
SELECT
    COALESCE(a.year, o.year) AS year,
    COALESCE(a.category, o.category) AS category,
    COALESCE(a.particular, o.particular) AS particular,
    COALESCE(a.region_code, o.region_code) AS region_code,
    a.appropriation_amount,
    o.obligation_amount,
    CASE
        WHEN a.source_present = 1 AND o.source_present = 1
            THEN 'MATCHED'
        WHEN a.source_present = 1 THEN 'APPROPRIATION_ONLY'
        ELSE 'OBLIGATION_ONLY'
    END AS match_status
FROM gold_appropriations_normalized a
FULL OUTER JOIN gold_obligations_normalized o
    ON a.year = o.year
   AND a.category = o.category
   AND a.particular = o.particular
   AND a.region_code = o.region_code;

-- Step 9: Notebook code cell
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty appropriation detail batch.')
FROM gold_appropriations_normalized;
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty obligation detail batch.')
FROM gold_obligations_normalized;

-- Step 11: Notebook code cell
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT year_id) AND COUNT(*) = COUNT(DISTINCT year),
    'Invalid year dimension keys.')
FROM pondolens.dev_gold.dim_year;

SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT location_id), 'Invalid location IDs.')
FROM pondolens.dev_gold.dim_location;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Invalid normalized region keys.')
FROM (
    SELECT NULLIF(UPPER(TRIM(location_code)), '') AS code
    FROM pondolens.dev_gold.dim_location
    GROUP BY NULLIF(UPPER(TRIM(location_code)), '')
    HAVING COUNT(*) > 1 OR code IS NULL
);

SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT particular_id), 'Invalid particular IDs.')
FROM pondolens.dev_gold.dim_particular;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Invalid normalized particular keys.')
FROM (
    SELECT NULLIF(UPPER(TRIM(category)), '') AS category_key,
           NULLIF(UPPER(TRIM(particular)), '') AS particular_key
    FROM pondolens.dev_gold.dim_particular
    GROUP BY NULLIF(UPPER(TRIM(category)), ''), NULLIF(UPPER(TRIM(particular)), '')
    HAVING COUNT(*) > 1 OR category_key IS NULL OR particular_key IS NULL
);

-- Step 12: Notebook code cell
CREATE OR REPLACE TEMP VIEW gold_regional_expenditure_resolved AS
SELECT y.year_id, r.location_id AS region_id, p.particular_id, s.*
FROM gold_regional_expenditure_prepared s
LEFT JOIN pondolens.dev_gold.dim_year y ON s.year = y.year
LEFT JOIN pondolens.dev_gold.dim_location r
    ON s.region_code = UPPER(TRIM(r.location_code))
LEFT JOIN pondolens.dev_gold.dim_particular p
    ON s.category = UPPER(TRIM(p.category))
   AND s.particular = UPPER(TRIM(p.particular));

-- Step 13: Notebook code cell
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty fact batch.')
FROM gold_regional_expenditure_resolved;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Unresolved dimension keys.')
FROM gold_regional_expenditure_resolved
WHERE year_id IS NULL
   OR region_id IS NULL
   OR particular_id IS NULL;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate fact observation keys.')
FROM (
    SELECT year_id, region_id, particular_id
    FROM gold_regional_expenditure_resolved
    GROUP BY year_id, region_id, particular_id
    HAVING COUNT(*) > 1
);

-- Step 15: Notebook code cell
CREATE OR REPLACE TEMP VIEW gold_expenditure_reconciliation AS
WITH expected AS (
    SELECT 'APPROPRIATION' AS source, year, COUNT(*) AS rows,
           COUNT(appropriation_amount) AS valued_rows, SUM(appropriation_amount) AS amount
    FROM gold_appropriations_normalized GROUP BY year
    UNION ALL
    SELECT 'OBLIGATION', year, COUNT(*), COUNT(obligation_amount), SUM(obligation_amount)
    FROM gold_obligations_normalized GROUP BY year
), actual AS (
    SELECT 'APPROPRIATION' AS source, year, COUNT(*) AS rows,
           COUNT(appropriation_amount) AS valued_rows, SUM(appropriation_amount) AS amount
    FROM gold_regional_expenditure_resolved
    WHERE match_status IN ('MATCHED', 'APPROPRIATION_ONLY') GROUP BY year
    UNION ALL
    SELECT 'OBLIGATION', year, COUNT(*), COUNT(obligation_amount), SUM(obligation_amount)
    FROM gold_regional_expenditure_resolved
    WHERE match_status IN ('MATCHED', 'OBLIGATION_ONLY') GROUP BY year
)
SELECT e.source, e.year, e.rows AS source_rows, a.rows AS resolved_rows,
       e.amount AS source_amount, a.amount AS resolved_amount,
       (e.rows <=> a.rows) AND (e.valued_rows <=> a.valued_rows)
       AND (e.amount <=> a.amount) AS passed
FROM expected e FULL OUTER JOIN actual a
    ON e.source = a.source AND e.year = a.year;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Source reconciliation failed.')
FROM gold_expenditure_reconciliation WHERE NOT passed OR passed IS NULL;

-- Step 17: Notebook code cell
SET TIME ZONE 'UTC';

CREATE TABLE IF NOT EXISTS pondolens.dev_gold.fact_regional_expenditure (
    fact_regional_expenditure_id BIGINT NOT NULL,
    year_id INT NOT NULL,
    region_id INT NOT NULL,
    particular_id INT NOT NULL,
    appropriation_amount DECIMAL(20,4),
    obligation_amount DECIMAL(20,4),
    spending_difference DECIMAL(20,4),
    difference_percent DECIMAL(20,4)
)
USING DELTA;

-- Step 18: Notebook code cell
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty fact batch.')
FROM gold_regional_expenditure_resolved;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Unresolved dimension keys.')
FROM gold_regional_expenditure_resolved
WHERE year_id IS NULL OR region_id IS NULL OR particular_id IS NULL;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate source fact keys.')
FROM (
    SELECT year_id, region_id, particular_id
    FROM gold_regional_expenditure_resolved
    GROUP BY year_id, region_id, particular_id
    HAVING COUNT(*) > 1
);

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT fact_regional_expenditure_id)
    AND COALESCE(COUNT_IF(fact_regional_expenditure_id < 60000), 0) = 0,
    'Invalid or duplicate target IDs.'
)
FROM pondolens.dev_gold.fact_regional_expenditure;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate target fact keys.')
FROM (
    SELECT year_id, region_id, particular_id
    FROM pondolens.dev_gold.fact_regional_expenditure
    GROUP BY year_id, region_id, particular_id
    HAVING COUNT(*) > 1
);

-- Step 19: Notebook code cell
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Target has unresolved dimension references.')
FROM pondolens.dev_gold.fact_regional_expenditure t
LEFT JOIN pondolens.dev_gold.dim_year y ON t.year_id = y.year_id
LEFT JOIN pondolens.dev_gold.dim_location r ON t.region_id = r.location_id
LEFT JOIN pondolens.dev_gold.dim_particular p ON t.particular_id = p.particular_id
WHERE y.year_id IS NULL OR r.location_id IS NULL OR p.particular_id IS NULL;

-- Step 21: Notebook code cell
CREATE OR REPLACE TEMP VIEW gold_regional_expenditure_upsert AS
SELECT
    COALESCE(t.fact_regional_expenditure_id,
        m.next_id - 1 + ROW_NUMBER() OVER (
            PARTITION BY (t.fact_regional_expenditure_id IS NULL)
            ORDER BY s.year_id, s.region_id, s.particular_id
        )
    ) AS fact_regional_expenditure_id,
    s.year_id, s.region_id, s.particular_id,
    CAST(s.appropriation_amount AS DECIMAL(20,4)) AS appropriation_amount,
    CAST(s.obligation_amount AS DECIMAL(20,4)) AS obligation_amount,
    CAST(s.appropriation_amount - s.obligation_amount AS DECIMAL(20,4)) AS spending_difference,
    CAST(((s.appropriation_amount - s.obligation_amount) /
         NULLIF(s.appropriation_amount, 0)) * 100 AS DECIMAL(20,4)) AS difference_percent
FROM gold_regional_expenditure_resolved s
LEFT JOIN pondolens.dev_gold.fact_regional_expenditure t
    ON s.year_id = t.year_id AND s.region_id = t.region_id
   AND s.particular_id = t.particular_id
CROSS JOIN (
    SELECT GREATEST(COALESCE(MAX(fact_regional_expenditure_id) + 1, 60000), 60000) AS next_id
    FROM pondolens.dev_gold.fact_regional_expenditure
) m;

-- Step 23: Notebook code cell
MERGE INTO pondolens.dev_gold.fact_regional_expenditure t
USING gold_regional_expenditure_upsert s
ON t.year_id = s.year_id AND t.region_id = s.region_id
   AND t.particular_id = s.particular_id
WHEN MATCHED AND (
       NOT (t.appropriation_amount <=> s.appropriation_amount)
    OR NOT (t.obligation_amount <=> s.obligation_amount)
    OR NOT (t.spending_difference <=> s.spending_difference)
    OR NOT (t.difference_percent <=> s.difference_percent)
) THEN UPDATE SET
    t.appropriation_amount = s.appropriation_amount,
    t.obligation_amount = s.obligation_amount,
    t.spending_difference = s.spending_difference,
    t.difference_percent = s.difference_percent
WHEN NOT MATCHED THEN INSERT (
    fact_regional_expenditure_id, year_id, region_id, particular_id,
    appropriation_amount, obligation_amount, spending_difference, difference_percent
) VALUES (
    s.fact_regional_expenditure_id, s.year_id, s.region_id, s.particular_id,
    s.appropriation_amount, s.obligation_amount, s.spending_difference, s.difference_percent
);

-- Step 25: Notebook code cell
SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT fact_regional_expenditure_id)
    AND COALESCE(COUNT_IF(fact_regional_expenditure_id < 60000), 0) = 0,
    'Duplicate or out-of-range fact IDs after MERGE.')
FROM pondolens.dev_gold.fact_regional_expenditure;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate fact keys after MERGE.')
FROM (
    SELECT year_id, region_id, particular_id
    FROM pondolens.dev_gold.fact_regional_expenditure
    GROUP BY year_id, region_id, particular_id HAVING COUNT(*) > 1
);

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Post-MERGE reconciliation failed.')
FROM gold_regional_expenditure_resolved s
LEFT JOIN pondolens.dev_gold.fact_regional_expenditure t
    ON s.year_id = t.year_id AND s.region_id = t.region_id
   AND s.particular_id = t.particular_id
WHERE t.fact_regional_expenditure_id IS NULL
   OR NOT (CAST(s.appropriation_amount AS DECIMAL(20,4)) <=> t.appropriation_amount)
   OR NOT (CAST(s.obligation_amount AS DECIMAL(20,4)) <=> t.obligation_amount)
   OR NOT (CAST(s.appropriation_amount - s.obligation_amount AS DECIMAL(20,4))
           <=> t.spending_difference)
   OR NOT (CAST(((s.appropriation_amount - s.obligation_amount) /
            NULLIF(s.appropriation_amount, 0)) * 100 AS DECIMAL(20,4))
           <=> t.difference_percent);

SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT fact_regional_expenditure_id) AS unique_ids,
       MIN(fact_regional_expenditure_id) AS first_id,
       MAX(fact_regional_expenditure_id) AS last_id
FROM pondolens.dev_gold.fact_regional_expenditure;

SELECT year, match_status, COUNT(*) AS row_count
FROM gold_regional_expenditure_resolved
GROUP BY year, match_status ORDER BY year, match_status;
