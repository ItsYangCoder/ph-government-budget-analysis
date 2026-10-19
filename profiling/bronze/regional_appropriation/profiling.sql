-- Regional GAA Profiling
-- Source: regional_appropriation_profiling.ipynb
-- Table: pondolens.dev_bronze.regional_appropriation
-- Read-only profiling queries


-- 1. Structure and coverage

DESCRIBE TABLE pondolens.dev_bronze.regional_appropriation;

SELECT *
FROM pondolens.dev_bronze.regional_appropriation
LIMIT 10;

SELECT DISTINCT(particulars)
FROM pondolens.dev_bronze.regional_appropriation;

-- List of all regions

SELECT
    DISTINCT(regions) as region_list
FROM pondolens.dev_bronze.regional_appropriation;

SELECT COUNT(*)
FROM pondolens.dev_bronze.regional_appropriation;


-- 2. Data quality

-- Null counts
SELECT
    COUNT(*) as total_rows,
    COUNT_IF(source_name IS NULL) as source_name_nulls,
    COUNT_IF(source_page IS NULL) as source_page_nulls,
    COUNT_IF(price_basis IS NULL) as price_basis_nulls,
    COUNT_IF(year IS NULL) as year_nulls,
    COUNT_IF(category IS NULL) as category_nulls,
    COUNT_IF(particulars IS NULL) as particulars_nulls,
    COUNT_IF(regions IS NULL) as regions_nulls,
    COUNT_IF(expenditure_amount IS NULL) as expenditure_amount_nulls,
    COUNT_IF(unit_amount IS NULL) as unit_amount_nulls
FROM
    pondolens.dev_bronze.regional_appropriation;

-- Duplicates
SELECT
    source_name,
    source_page,
    price_basis,
    year,
    category,
    particulars,
    regions,
    expenditure_amount,
    unit_amount,
    COUNT(*) AS duplicate_count
FROM pondolens.dev_bronze.regional_appropriation
GROUP BY
    source_name,
    source_page,
    price_basis,
    year,
    category,
    particulars,
    regions,
    expenditure_amount,
    unit_amount
HAVING COUNT(*) > 1;

-- Check for special characters 

WITH column_values AS (
    SELECT
        source_name AS file_name,
        STACK(
            9,
            'source_name', CAST(source_name AS STRING),
            'source_page', CAST(source_page AS STRING),
            'price_basis', CAST(price_basis AS STRING),
            'year', CAST(year AS STRING),
            'category', CAST(category AS STRING),
            'particulars', CAST(particulars AS STRING),
            'regions', CAST(regions AS STRING),
            'expenditure_amount', CAST(expenditure_amount AS STRING),
            'unit_amount', CAST(unit_amount AS STRING)
        ) AS (column_name, column_value)
    FROM pondolens.dev_bronze.regional_appropriation
)
SELECT
    file_name,
    column_name,
    column_value,
    COUNT(*) AS occurrences
FROM column_values
WHERE column_value RLIKE '[^a-zA-Z0-9 ]'
GROUP BY file_name, column_name, column_value
ORDER BY column_name, occurrences DESC;


-- 3. Reconcile totals

WITH reconciliation AS (
    SELECT
        year,
        category,
        particulars,

        SUM(
            CASE WHEN regions = 'Total'
            THEN TRY_CAST(expenditure_amount AS DECIMAL(20,2))
            ELSE 0 END
        ) AS reported_total,

        SUM(
            CASE WHEN regions <> 'Total'
            THEN TRY_CAST(expenditure_amount AS DECIMAL(20,2))
            ELSE 0 END
        ) AS calculated_total

    FROM pondolens.dev_bronze.regional_appropriation
    GROUP BY year, category, particulars
)

SELECT
    *,
    reported_total - calculated_total AS difference,
    CASE
        WHEN reported_total = calculated_total THEN 'MATCH'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY category, particulars;

WITH reconciliation AS (
    SELECT
        year,
        category,
        regions,

        SUM(
            CASE WHEN particulars = 'All'
            THEN TRY_CAST(expenditure_amount AS DECIMAL(20,2))
            ELSE 0 END
        ) AS reported_total,

        SUM(
            CASE WHEN particulars <> 'All'
            THEN TRY_CAST(expenditure_amount AS DECIMAL(20,2))
            ELSE 0 END
        ) AS calculated_total

    FROM pondolens.dev_bronze.regional_appropriation
    WHERE category IN (
        'DEPARTMENTS',
        'SPECIAL PURPOSE FUNDS'
    )
    GROUP BY year, category, regions
)

SELECT
    *,
    reported_total - calculated_total AS difference,
    CASE
        WHEN reported_total = calculated_total THEN 'MATCH'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY category, regions;

WITH reconciliation AS (
    SELECT
        year,
        regions,

        SUM(
            CASE
                WHEN category = 'GRAND TOTAL'
                AND particulars = 'All'
                THEN TRY_CAST(expenditure_amount AS DECIMAL(20,2))
                ELSE 0
            END
        ) AS reported_grand_total,

        SUM(
            CASE
                WHEN category IN (
                    'DEPARTMENTS',
                    'SPECIAL PURPOSE FUNDS'
                )
                AND particulars = 'All'
                THEN TRY_CAST(expenditure_amount AS DECIMAL(20,2))
                ELSE 0
            END
        ) AS calculated_grand_total

    FROM pondolens.dev_bronze.regional_appropriation
    GROUP BY year, regions
)

SELECT
    *,
    reported_grand_total - calculated_grand_total AS difference,
    CASE
        WHEN reported_grand_total = calculated_grand_total
        THEN 'MATCH'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY regions;
