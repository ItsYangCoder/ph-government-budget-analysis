-- Dataset: regional_appropriation
-- Table: pondolens.dev_bronze.regional_appropriation
-- Owner: Razzelle Boreros
-- Scope: active
-- Execute the complete file in one Databricks SQL session.
-- Persistent tables are read-only; session TEMP VIEWs are allowed.
-- Evidence and unresolved checks: findings.md. Column definitions: data_dictionary.md.

-- Regional appropriations profiling 
-- Documented by: Razzelle Boreros
-- Read-only profiling; temporary views do not change Bronze.
-- Reconciliation uses the agreed dash-as-zero interpretation.
-- Reported results and pending checks are listed in findings.md.

-- 1. Review column types and prepare values for checking.
DESCRIBE TABLE pondolens.dev_bronze.regional_appropriation;

CREATE OR REPLACE TEMP VIEW gaa_profile AS
WITH cleaned AS (
    SELECT
        *,
        NULLIF(UPPER(TRIM(category)), '') AS category_key,
        NULLIF(UPPER(TRIM(particulars)), '') AS particular_key,
        NULLIF(
            REGEXP_REPLACE(UPPER(TRIM(regions)), r'[^A-Z0-9]', ''),
            ''
        ) AS region_key,
        NULLIF(UPPER(TRIM(price_basis)), '') AS basis_key,
        TRIM(CAST(year AS STRING)) AS year_text,
        TRIM(CAST(expenditure_amount AS STRING)) AS amount_text
    FROM pondolens.dev_bronze.regional_appropriation
)
SELECT
    *,
    TRY_CAST(year_text AS INT) AS year_num,
    CASE
        WHEN amount_text IN ('-', '–', '—')
            THEN CAST(0 AS DECIMAL(20,2))
        ELSE TRY_CAST(
            REPLACE(amount_text, ',', '')
            AS DECIMAL(20,2)
        )
    END AS amount_num
FROM cleaned;


-- 2. Check total rows, source details and coverage for all five years.
SELECT
    COUNT(*) AS total_rows,
    MIN(year_num) AS earliest_year,
    MAX(year_num) AS latest_year,
    COUNT(DISTINCT year_num) AS distinct_years,
    COUNT_IF(year_num IS NULL) AS unparseable_years,
    COUNT_IF(year_num NOT BETWEEN 2021 AND 2025) AS rows_outside_scope
FROM gaa_profile;

WITH years AS (
    SELECT EXPLODE(SEQUENCE(2021, 2025)) AS year
),
counts AS (
    SELECT
        year_num,
        COUNT(*) AS row_count
    FROM gaa_profile
    GROUP BY year_num
)
SELECT
    y.year,
    COALESCE(c.row_count, 0) AS row_count,
    CASE
        WHEN c.row_count IS NULL THEN 'MISSING'
        ELSE 'PRESENT'
    END AS coverage
FROM years y
LEFT JOIN counts c
    ON y.year = c.year_num
ORDER BY y.year;

SELECT
    year,
    source_name,
    source_page,
    price_basis,
    unit_amount,
    COUNT(*) AS row_count,
    COUNT_IF(amount_text IN ('-', '–', '—')) AS dash_amounts
FROM gaa_profile
GROUP BY
    year, source_name, source_page, price_basis, unit_amount
ORDER BY year, source_name, source_page;


-- 3. Check NULLs, blanks, dash markers and invalid numeric values.
WITH field_values AS (
    SELECT
        field,
        TRIM(raw_value) AS raw_value
    FROM gaa_profile
    LATERAL VIEW STACK(
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
    ) s AS field, raw_value
),
checked AS (
    SELECT
        *,
        raw_value IS NULL
            OR LOWER(raw_value) IN ('', 'null') AS is_missing,
        TRY_CAST(
            REPLACE(raw_value, ',', '')
            AS DECIMAL(20,2)
        ) AS numeric_value
    FROM field_values
)
SELECT
    field,
    COUNT(*) AS total_rows,
    COUNT_IF(raw_value IS NULL) AS null_values,
    COUNT_IF(raw_value = '') AS blank_values,
    COUNT_IF(LOWER(raw_value) = 'null') AS literal_null_values,
    COUNT_IF(raw_value IN ('-', '–', '—')) AS dash_markers,

    CASE WHEN field IN ('year', 'expenditure_amount') THEN
        COUNT_IF(
            NOT is_missing
            AND (
                (
                    field = 'year'
                    AND TRY_CAST(raw_value AS INT) IS NULL
                )
                OR (
                    field = 'expenditure_amount'
                    AND raw_value NOT IN ('-', '–', '—')
                    AND numeric_value IS NULL
                )
            )
        )
    END AS invalid_numeric_values

FROM checked
GROUP BY field
ORDER BY field;

SELECT
    COUNT_IF(amount_num < 0) AS negative_amounts,
    COUNT_IF(
        amount_num = 0
        AND amount_text NOT IN ('-', '–', '—')
    ) AS explicit_zero_amounts,
    COUNT_IF(
        amount_text IN ('-', '–', '—')
    ) AS dash_amounts_treated_as_zero,
    MIN(amount_num) AS minimum_amount_thousand_pesos,
    MAX(amount_num) AS maximum_amount_thousand_pesos
FROM gaa_profile;


-- 4. Review geographical labels, particulars and total/detail rows.
SELECT
    regions AS source_region,
    region_key,

    CASE
        WHEN region_key = 'TOTAL'
            THEN 'geographic_total'
        WHEN region_key IN (
            'NW', 'NATIONWIDE', 'NATIONAWIDE',
            'CO', 'CENTRALOFFICE'
        )
            THEN 'nonregional'
        WHEN region_key IN ('PHL', 'PHILIPPINES')
            THEN 'national'
        WHEN region_key IS NULL OR region_key = 'NULL'
            THEN 'unknown'
        ELSE 'regional_candidate'
    END AS geographic_level,

    COUNT(*) AS row_count
FROM gaa_profile
GROUP BY regions, region_key
ORDER BY geographic_level, source_region;

SELECT
    category_key AS category,
    particular_key AS particular,
    CASE
        WHEN particular_key = 'ALL' THEN 'aggregate'
        ELSE 'detail'
    END AS row_type,
    COUNT(*) AS row_count
FROM gaa_profile
GROUP BY category_key, particular_key
ORDER BY category, particular;


-- 5. Check duplicate data rows and repeated keys before region mapping.
WITH records AS (
    SELECT
        'Duplicate data rows' AS check_name,
        TO_JSON(STRUCT(
            source_name,
            source_page,
            price_basis,
            year,
            category,
            particulars,
            regions,
            expenditure_amount,
            unit_amount
        )) AS record
    FROM gaa_profile

    UNION ALL

    SELECT
        'Bronze key: year + category + particular + area + basis',
        TO_JSON(STRUCT(
            year_num,
            category_key,
            particular_key,
            region_key,
            basis_key
        ))
    FROM gaa_profile

    UNION ALL

    SELECT
        'Candidate Silver key: year + category + particular + area',
        TO_JSON(STRUCT(
            year_num,
            category_key,
            particular_key,
            region_key
        ))
    FROM gaa_profile
    WHERE year_num BETWEEN 2021 AND 2025
      AND COALESCE(particular_key, '') <> 'ALL'
      AND COALESCE(region_key, '') <> 'TOTAL'
),
grouped AS (
    SELECT
        check_name,
        record,
        COUNT(*) AS occurrences
    FROM records
    GROUP BY check_name, record
),
labels AS (
    SELECT * FROM VALUES
        ('Duplicate data rows'),
        ('Bronze key: year + category + particular + area + basis'),
        ('Candidate Silver key: year + category + particular + area')
    AS t(check_name)
)
SELECT
    l.check_name,
    COALESCE(SUM(g.occurrences), 0) AS total_rows,
    COUNT_IF(g.occurrences > 1) AS duplicate_groups,
    COALESCE(
        SUM(GREATEST(g.occurrences - 1, 0)),
        0
    ) AS excess_rows
FROM labels l
LEFT JOIN grouped g
    ON l.check_name = g.check_name
GROUP BY l.check_name
ORDER BY l.check_name;


-- 6. Review punctuation; special characters are not automatically errors.
WITH column_values AS (
    SELECT
        source_name AS file_name,
        column_name,
        column_value
    FROM gaa_profile
    LATERAL VIEW STACK(
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
    ) s AS column_name, column_value
)
SELECT
    file_name,
    column_name,
    column_value,
    COUNT(*) AS occurrences
FROM column_values
WHERE column_value RLIKE '[^a-zA-Z0-9 ]'
GROUP BY file_name, column_name, column_value
ORDER BY column_name, file_name, occurrences DESC;


-- 7. Reconcile all three totals; dashes are zero.
-- Missing or invalid amounts require review. Amounts remain in thousand pesos.
WITH totals AS (
    SELECT
        'Geographical total' AS check_name,
        year_num AS year,
        category_key AS group_1,
        particular_key AS group_2,
        COUNT_IF(region_key = 'TOTAL') AS reported_rows,
        COUNT_IF(region_key <> 'TOTAL') AS detail_rows,
        COUNT(DISTINCT CASE
            WHEN region_key <> 'TOTAL' THEN region_key
        END) AS detail_groups,
        COUNT_IF(
            amount_num IS NULL
            OR year_num IS NULL
            OR category_key IS NULL
            OR particular_key IS NULL
            OR region_key IS NULL
        ) AS unresolved_rows,
        SUM(CASE
            WHEN region_key = 'TOTAL' THEN amount_num
        END) AS reported_total,
        SUM(CASE
            WHEN region_key <> 'TOTAL' THEN amount_num
        END) AS calculated_total
    FROM gaa_profile
    GROUP BY year_num, category_key, particular_key

    UNION ALL

    SELECT
        'Category All subtotal',
        year_num,
        category_key,
        region_key,
        COUNT_IF(particular_key = 'ALL'),
        COUNT_IF(particular_key <> 'ALL'),
        COUNT(DISTINCT CASE
            WHEN particular_key <> 'ALL' THEN particular_key
        END),
        COUNT_IF(
            amount_num IS NULL
            OR year_num IS NULL
            OR particular_key IS NULL
            OR region_key IS NULL
        ),
        SUM(CASE
            WHEN particular_key = 'ALL' THEN amount_num
        END),
        SUM(CASE
            WHEN particular_key <> 'ALL' THEN amount_num
        END)
    FROM gaa_profile
    WHERE category_key IN (
        'DEPARTMENTS',
        'SPECIAL PURPOSE FUNDS'
    )
    GROUP BY year_num, category_key, region_key

    UNION ALL

    SELECT
        'Grand total',
        year_num,
        'GRAND TOTAL',
        region_key,
        COUNT_IF(category_key = 'GRAND TOTAL'),
        COUNT_IF(category_key IN (
            'DEPARTMENTS',
            'SPECIAL PURPOSE FUNDS'
        )),
        COUNT(DISTINCT CASE
            WHEN category_key <> 'GRAND TOTAL' THEN category_key
        END),
        COUNT_IF(
            amount_num IS NULL
            OR year_num IS NULL
            OR region_key IS NULL
        ),
        SUM(CASE
            WHEN category_key = 'GRAND TOTAL' THEN amount_num
        END),
        SUM(CASE
            WHEN category_key <> 'GRAND TOTAL' THEN amount_num
        END)
    FROM gaa_profile
    WHERE particular_key = 'ALL'
      AND category_key IN (
          'GRAND TOTAL',
          'DEPARTMENTS',
          'SPECIAL PURPOSE FUNDS'
      )
    GROUP BY year_num, region_key
)
SELECT
    *,
    reported_total - calculated_total AS difference,

    CASE
        WHEN reported_rows <> 1
          OR detail_rows = 0
          OR unresolved_rows > 0
          OR detail_rows <> detail_groups
          OR reported_total IS NULL
          OR calculated_total IS NULL
          OR (
              check_name = 'Grand total'
              AND detail_groups <> 2
          )
            THEN 'REVIEW'
        WHEN reported_total = calculated_total
            THEN 'MATCH'
        ELSE 'ISSUE'
    END AS status

FROM totals
ORDER BY check_name, year, group_1, group_2;


-- 8. Validate original year labels without silently truncating fractions.
SELECT year_text, COUNT(*) AS row_count
FROM gaa_profile
WHERE NOT (year_text RLIKE '^[0-9]{4}$') OR year_num IS NULL
GROUP BY year_text;

-- 9. Check ingestion metadata. Results are pending until this query is run.
SELECT _source_file, _run_id, COUNT(*) AS row_count,
    COUNT_IF(
        NULLIF(TRIM(_drive_file_id), '') IS NULL
        OR NULLIF(TRIM(_source_file), '') IS NULL
        OR NULLIF(TRIM(_landing_file), '') IS NULL
        OR NULLIF(TRIM(_content_hash), '') IS NULL
        OR NULLIF(TRIM(_dataset_hash), '') IS NULL
        OR NULLIF(TRIM(_run_id), '') IS NULL
        OR _ingested_at IS NULL
    ) AS incomplete_lineage_rows,
    COUNT_IF(NULLIF(TRIM(_rescued_data), '') IS NOT NULL) AS rescued_rows,
    MIN(_ingested_at) AS earliest_ingestion,
    MAX(_ingested_at) AS latest_ingestion
FROM gaa_profile
GROUP BY _source_file, _run_id;
