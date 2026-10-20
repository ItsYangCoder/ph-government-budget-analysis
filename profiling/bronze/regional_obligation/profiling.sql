-- Regional Expenditure obligationss Profiling
-- Table: pondolens.dev_bronze.regional_obligations
-- Source: DBM BESF Table B.6.a, Regional Allocation of the Expenditure Program, CY 2021 to 2025 (Actual obligationss)
-- Notes and findings: mia_regional_obligations_profiling_doc.md
-- Read-only profiling queries. Each query returns its own result table.


-- 1. DATASET UNDERSTANDING

-- 1.1 Table schema
DESCRIBE TABLE pondolens.dev_bronze.regional_obligations;

-- 1.2 Sample rows
SELECT *
FROM pondolens.dev_bronze.regional_obligations
LIMIT 10;

-- 1.3 Row count and coverage
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT year) AS years,
    MIN(year) AS earliest_year,
    MAX(year) AS latest_year,
    COUNT(DISTINCT source_name) AS source_files,
    COUNT(DISTINCT category) AS categories,
    COUNT(DISTINCT particulars) AS particulars,
    COUNT(DISTINCT regions) AS region_labels,
    COUNT(DISTINCT price_basis) AS price_bases,
    COUNT(DISTINCT unit_amount) AS units
FROM pondolens.dev_bronze.regional_obligations;

-- 1.4 Rows by source file and PDF page
SELECT
    year,
    source_name,
    source_page,
    COUNT(*) AS row_count,
    COUNT(DISTINCT regions) AS region_columns,
    COUNT(DISTINCT particulars) AS particulars
FROM pondolens.dev_bronze.regional_obligations
GROUP BY year, source_name, source_page
ORDER BY year, source_page;

-- 1.5 Number of particulars per category and year
SELECT
    category,
    COUNT_IF(year = 2021) AS y2021,
    COUNT_IF(year = 2022) AS y2022,
    COUNT_IF(year = 2023) AS y2023,
    COUNT_IF(year = 2024) AS y2024,
    COUNT_IF(year = 2025) AS y2025
FROM (
    SELECT DISTINCT year, category, particulars
    FROM pondolens.dev_bronze.regional_obligations
)
GROUP BY category
ORDER BY category;

-- 1.6 Row types: detail rows vs subtotal and total rows
SELECT
    CASE
        WHEN category = 'GRAND TOTAL' THEN 'grand total'
        WHEN particulars = 'All' THEN 'category subtotal'
        ELSE 'agency or fund (detail)'
    END AS row_type,
    CASE
        WHEN regions = 'Total' THEN 'total column'
        WHEN regions IN ('Nationwide', 'Central Office') THEN 'not a region'
        ELSE 'region'
    END AS location_type,
    COUNT(*) AS row_count
FROM pondolens.dev_bronze.regional_obligations
GROUP BY 1, 2
ORDER BY 1, 2;


-- 2. COMPLETENESS

-- 2.1 Null or blank values per column
SELECT
    COUNT(*) AS total_rows,
    COUNT_IF(source_name IS NULL OR TRIM(source_name) = '') AS source_name_missing,
    COUNT_IF(source_page IS NULL OR TRIM(source_page) = '') AS source_page_missing,
    COUNT_IF(price_basis IS NULL OR TRIM(price_basis) = '') AS price_basis_missing,
    COUNT_IF(year IS NULL OR TRIM(year) = '') AS year_missing,
    COUNT_IF(category IS NULL OR TRIM(category) = '') AS category_missing,
    COUNT_IF(particulars IS NULL OR TRIM(particulars) = '') AS particulars_missing,
    COUNT_IF(regions IS NULL OR TRIM(regions) = '') AS regions_missing,
    COUNT_IF(expenditure_amount IS NULL OR TRIM(expenditure_amount) = '') AS amount_blank,
    COUNT_IF(TRIM(expenditure_amount) = '-') AS amount_dash,
    COUNT_IF(unit_amount IS NULL OR TRIM(unit_amount) = '') AS unit_missing
FROM pondolens.dev_bronze.regional_obligations;

-- 2.2 Where the blank amounts are (expected: 2025 Automatic Appropriations only)
SELECT
    year,
    category,
    particulars,
    COUNT(*) AS blank_amounts
FROM pondolens.dev_bronze.regional_obligations
WHERE expenditure_amount IS NULL OR TRIM(expenditure_amount) = ''
GROUP BY year, category, particulars
ORDER BY year, category, particulars;

-- 2.3 Year coverage per region label (expected: Negros Island Region in 2025 only)
SELECT
    regions,
    COUNT_IF(year = 2021) AS y2021,
    COUNT_IF(year = 2022) AS y2022,
    COUNT_IF(year = 2023) AS y2023,
    COUNT_IF(year = 2024) AS y2024,
    COUNT_IF(year = 2025) AS y2025
FROM pondolens.dev_bronze.regional_obligations
GROUP BY regions
ORDER BY regions;

-- 2.4 Particulars not present in all five years
SELECT
    particulars,
    CONCAT_WS(', ', ARRAY_SORT(COLLECT_SET(CAST(year AS STRING)))) AS years_present,
    CONCAT_WS(', ', ARRAY_SORT(COLLECT_SET(category))) AS categories
FROM pondolens.dev_bronze.regional_obligations
GROUP BY particulars
HAVING COUNT(DISTINCT year) < 5
ORDER BY years_present, particulars;


-- 3. UNIQUENESS

-- 3.1 Exact duplicate rows. Expected: no rows.
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
FROM pondolens.dev_bronze.regional_obligations
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

-- 3.2 Repeated business keys: year + category + particulars + regions. Expected: no rows.
SELECT
    year,
    category,
    particulars,
    regions,
    COUNT(*) AS occurrences,
    COUNT(DISTINCT expenditure_amount) AS distinct_amounts
FROM pondolens.dev_bronze.regional_obligations
GROUP BY year, category, particulars, regions
HAVING COUNT(*) > 1;

-- 3.3 Each region appears on only one PDF page per year. Expected: no rows.
SELECT
    year,
    regions,
    COUNT(DISTINCT source_page) AS pages
FROM pondolens.dev_bronze.regional_obligations
GROUP BY year, regions
HAVING COUNT(DISTINCT source_page) > 1;


-- 4. VALIDITY

-- 4.1 Parse values for profiling. Raw values are kept so '-' and blank stay visible.
CREATE OR REPLACE TEMP VIEW regional_obligations_profile AS
SELECT
    TRY_CAST(year AS INT) AS year,
    TRY_CAST(source_page AS INT) AS source_page,
    source_name,
    TRIM(category) AS category,
    TRIM(particulars) AS particulars,
    TRIM(regions) AS regions,
    CASE
        WHEN TRIM(category) = 'GRAND TOTAL' THEN 'grand_total'
        WHEN TRIM(particulars) = 'All' THEN 'category_subtotal'
        ELSE 'detail'
    END AS row_type,
    CASE
        WHEN TRIM(regions) = 'Total' THEN 'total'
        WHEN TRIM(regions) = 'Nationwide' THEN 'nationwide'
        WHEN TRIM(regions) = 'Central Office' THEN 'central_office'
        ELSE 'region'
    END AS location_type,
    TRIM(expenditure_amount) AS amount_raw,
    TRY_CAST(REPLACE(TRIM(expenditure_amount), ',', '') AS DECIMAL(20, 2)) AS amount_thousand_php,
    CASE
        WHEN expenditure_amount IS NULL OR TRIM(expenditure_amount) = '' THEN 'blank'
        WHEN TRIM(expenditure_amount) = '-' THEN 'dash'
        WHEN TRY_CAST(REPLACE(TRIM(expenditure_amount), ',', '') AS DECIMAL(20, 2)) IS NULL THEN 'invalid'
        ELSE 'numeric'
    END AS amount_status
FROM pondolens.dev_bronze.regional_obligations;

-- 4.2 Parseability and ranges per year
SELECT
    year,
    COUNT(*) AS total_rows,
    COUNT_IF(amount_status = 'numeric') AS numeric_amounts,
    COUNT_IF(amount_status = 'dash') AS dash_markers,
    COUNT_IF(amount_status = 'blank') AS blank_amounts,
    COUNT_IF(amount_status = 'invalid') AS unexpected_nonnumeric,
    COUNT_IF(amount_thousand_php < 0) AS negative_amounts,
    COUNT_IF(amount_thousand_php = 0) AS zero_amounts,
    COUNT_IF(amount_thousand_php <> FLOOR(amount_thousand_php)) AS amounts_with_decimals,
    MIN(amount_thousand_php) AS minimum_amount,
    MAX(amount_thousand_php) AS maximum_amount
FROM regional_obligations_profile
GROUP BY year
ORDER BY year;

-- 4.3 Fixed columns: one value each. Expected: Actual obligationss, thousand pesos.
SELECT
    year,
    CONCAT_WS(' | ', COLLECT_SET(price_basis)) AS price_basis_values,
    CONCAT_WS(' | ', COLLECT_SET(unit_amount)) AS unit_values,
    CONCAT_WS(' | ', COLLECT_SET(source_name)) AS source_files
FROM pondolens.dev_bronze.regional_obligations
GROUP BY year
ORDER BY year;

-- 4.4 Special characters in text columns (parentheses, hyphen, comma, ampersand and period are allowed)
WITH column_values AS (
    SELECT
        STACK(
            4,
            'category', category,
            'particulars', particulars,
            'regions', regions,
            'expenditure_amount', expenditure_amount
        ) AS (column_name, column_value)
    FROM pondolens.dev_bronze.regional_obligations
)
SELECT
    column_name,
    column_value,
    COUNT(*) AS occurrences
FROM column_values
WHERE column_value RLIKE '[^a-zA-Z0-9 ()&,.-]'
   OR column_value <> TRIM(column_value)
   OR column_value LIKE '%  %'
GROUP BY column_name, column_value
ORDER BY column_name, occurrences DESC;


-- 5. CONSISTENCY

-- 5.1 Region labels and proposed team codes. Total, Nationwide and Central Office are not regions.
WITH region_ref AS (
    SELECT * FROM VALUES
        ('National Capital Region', 'NCR', 'NATIONAL CAPITAL REGION'),
        ('Cordillera Administrative Region', 'CAR', 'CORDILLERA ADMINISTRATIVE REGION'),
        ('Region I', 'I', 'ILOCOS REGION'),
        ('Region II', 'II', 'CAGAYAN VALLEY'),
        ('Region III', 'III', 'CENTRAL LUZON'),
        ('Region IVA', 'IVA', 'CALABARZON'),
        ('Region IVB', 'IVB', 'MIMAROPA REGION'),
        ('Region V', 'V', 'BICOL REGION'),
        ('Region VI', 'VI', 'WESTERN VISAYAS'),
        ('Negros Island Region', 'NIR', 'NEGROS ISLAND REGION'),
        ('Region VII', 'VII', 'CENTRAL VISAYAS'),
        ('Region VIII', 'VIII', 'EASTERN VISAYAS'),
        ('Region IX', 'IX', 'ZAMBOANGA PENINSULA'),
        ('Region X', 'X', 'NORTHERN MINDANAO'),
        ('Region XI', 'XI', 'DAVAO REGION'),
        ('Region XII', 'XII', 'SOCCSKSARGEN'),
        ('CARAGA', 'XIII', 'CARAGA'),
        ('BARMM', 'BARMM', 'BANGSAMORO AUTONOMOUS REGION IN MUSLIM MINDANAO')
    AS r(source_region, region_code, standard_region_name)
)
SELECT
    p.regions AS region_as_stored,
    p.location_type,
    r.region_code,
    r.standard_region_name,
    CASE
        WHEN p.location_type <> 'region' THEN 'NOT A REGION'
        WHEN r.region_code IS NULL THEN 'UNMAPPED'
        ELSE 'MAPPED'
    END AS status,
    COUNT(*) AS row_count
FROM regional_obligations_profile p
LEFT JOIN region_ref r
    ON p.regions = r.source_region
GROUP BY p.regions, p.location_type, r.region_code, r.standard_region_name
ORDER BY status, r.region_code;

-- 5.2 Particulars that changed category across years (expected: Net Lending, debt interest)
SELECT
    particulars,
    CONCAT_WS(', ', ARRAY_SORT(COLLECT_SET(CONCAT(CAST(year AS STRING), ': ', category)))) AS year_and_category
FROM regional_obligations_profile
WHERE row_type = 'detail'
GROUP BY particulars
HAVING COUNT(DISTINCT category) > 1;

-- 5.3 Agencies whose name changed across years (same office, different label)
SELECT
    particulars,
    category,
    CONCAT_WS(', ', ARRAY_SORT(COLLECT_SET(CAST(year AS STRING)))) AS years_present
FROM regional_obligations_profile
WHERE LOWER(particulars) LIKE '%communications%'
   OR LOWER(particulars) LIKE '%press secretary%'
   OR LOWER(particulars) LIKE '%debt%'
   OR LOWER(particulars) LIKE '%interest%'
   OR LOWER(particulars) LIKE '%joint legislative%'
   OR LOWER(particulars) LIKE '%migrant workers%'
   OR LOWER(particulars) LIKE '%tax allotment%'
   OR LOWER(particulars) LIKE '%block grant%'
GROUP BY particulars, category
ORDER BY years_present, particulars;

-- 5.4 Particulars that differ only by case, spacing or punctuation. Expected: no rows.
SELECT
    UPPER(REGEXP_REPLACE(particulars, '[^A-Za-z0-9]', '')) AS normalized_name,
    CONCAT_WS(' | ', ARRAY_SORT(COLLECT_SET(particulars))) AS spellings,
    COUNT(DISTINCT particulars) AS variations
FROM regional_obligations_profile
GROUP BY UPPER(REGEXP_REPLACE(particulars, '[^A-Za-z0-9]', ''))
HAVING COUNT(DISTINCT particulars) > 1;

-- 5.5 Category totals per year (shows the 2025 change: Automatic Appropriations appears, Special Purpose Funds drops)
SELECT
    year,
    SUM(CASE WHEN category = 'DEPARTMENTS' THEN amount_thousand_php END) AS departments,
    SUM(CASE WHEN category = 'SPECIAL PURPOSE FUNDS' THEN amount_thousand_php END) AS special_purpose_funds,
    SUM(CASE WHEN category = 'AUTOMATIC APPROPRIATIONS' THEN amount_thousand_php END) AS automatic_appropriations,
    SUM(CASE WHEN category = 'GRAND TOTAL' THEN amount_thousand_php END) AS grand_total
FROM regional_obligations_profile
WHERE row_type IN ('category_subtotal', 'grand_total')
  AND location_type = 'total'
GROUP BY year
ORDER BY year;


-- 6. ACCURACY AND RECONCILIATION
-- Amounts are in thousand pesos and rounded in the PDF, so a difference of 1 is treated as rounding.

-- 6.1 Total column vs sum of Nationwide + Central Office + regions
WITH reconciliation AS (
    SELECT
        year,
        category,
        particulars,
        SUM(CASE WHEN location_type = 'total' THEN COALESCE(amount_thousand_php, 0) ELSE 0 END) AS reported_total,
        SUM(CASE WHEN location_type <> 'total' THEN COALESCE(amount_thousand_php, 0) ELSE 0 END) AS calculated_total
    FROM regional_obligations_profile
    GROUP BY year, category, particulars
)
SELECT
    *,
    reported_total - calculated_total AS difference,
    CASE
        WHEN reported_total = calculated_total THEN 'MATCH'
        WHEN ABS(reported_total - calculated_total) <= 1 THEN 'ROUNDING'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY status DESC, year, category, particulars;

-- 6.2 Category subtotal ('All') vs sum of its agencies or funds, per region
WITH reconciliation AS (
    SELECT
        year,
        category,
        regions,
        SUM(CASE WHEN row_type = 'category_subtotal' THEN COALESCE(amount_thousand_php, 0) ELSE 0 END) AS reported_total,
        SUM(CASE WHEN row_type = 'detail' THEN COALESCE(amount_thousand_php, 0) ELSE 0 END) AS calculated_total
    FROM regional_obligations_profile
    WHERE row_type <> 'grand_total'
    GROUP BY year, category, regions
)
SELECT
    *,
    reported_total - calculated_total AS difference,
    CASE
        WHEN reported_total = calculated_total THEN 'MATCH'
        WHEN ABS(reported_total - calculated_total) <= 1 THEN 'ROUNDING'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY status DESC, year, category, regions;

-- 6.3 Grand total vs sum of category subtotals, per region
WITH reconciliation AS (
    SELECT
        year,
        regions,
        SUM(CASE WHEN row_type = 'grand_total' THEN COALESCE(amount_thousand_php, 0) ELSE 0 END) AS reported_grand_total,
        SUM(CASE WHEN row_type = 'category_subtotal' THEN COALESCE(amount_thousand_php, 0) ELSE 0 END) AS calculated_grand_total
    FROM regional_obligations_profile
    GROUP BY year, regions
)
SELECT
    *,
    reported_grand_total - calculated_grand_total AS difference,
    CASE
        WHEN reported_grand_total = calculated_grand_total THEN 'MATCH'
        WHEN ABS(reported_grand_total - calculated_grand_total) <= 1 THEN 'ROUNDING'
        ELSE 'ISSUE'
    END AS status
FROM reconciliation
ORDER BY status DESC, year, regions;

-- 6.4 Share of the grand total that cannot be assigned to a region (Central Office and Nationwide)
WITH grand AS (
    SELECT year, location_type, SUM(amount_thousand_php) AS amount
    FROM regional_obligations_profile
    WHERE row_type = 'grand_total'
    GROUP BY year, location_type
)
SELECT
    year,
    MAX(CASE WHEN location_type = 'total' THEN amount END) AS grand_total,
    ROUND(100 * MAX(CASE WHEN location_type = 'central_office' THEN amount END)
        / MAX(CASE WHEN location_type = 'total' THEN amount END), 1) AS central_office_pct,
    ROUND(100 * MAX(CASE WHEN location_type = 'nationwide' THEN amount END)
        / MAX(CASE WHEN location_type = 'total' THEN amount END), 1) AS nationwide_pct,
    ROUND(100 * MAX(CASE WHEN location_type = 'region' THEN amount END)
        / MAX(CASE WHEN location_type = 'total' THEN amount END), 1) AS regions_pct
FROM grand
GROUP BY year
ORDER BY year;

-- 6.5 Trace back to the source PDF: compare these 10 values with the PDF table
SELECT
    year,
    source_name,
    source_page,
    category,
    particulars,
    regions,
    amount_raw
FROM regional_obligations_profile
WHERE amount_status = 'numeric'
ORDER BY RAND(42)
LIMIT 10;


-- 7. SILVER TREATMENT

-- 7.1 Silver preview: detail rows only, standard region codes and names, standard agency names, amounts in pesos
CREATE OR REPLACE TEMP VIEW regional_obligations_silver_preview AS
WITH region_ref AS (
    SELECT * FROM VALUES
        ('National Capital Region', 'NCR', 'NATIONAL CAPITAL REGION'),
        ('Cordillera Administrative Region', 'CAR', 'CORDILLERA ADMINISTRATIVE REGION'),
        ('Region I', 'I', 'ILOCOS REGION'),
        ('Region II', 'II', 'CAGAYAN VALLEY'),
        ('Region III', 'III', 'CENTRAL LUZON'),
        ('Region IVA', 'IVA', 'CALABARZON'),
        ('Region IVB', 'IVB', 'MIMAROPA REGION'),
        ('Region V', 'V', 'BICOL REGION'),
        ('Region VI', 'VI', 'WESTERN VISAYAS'),
        ('Negros Island Region', 'NIR', 'NEGROS ISLAND REGION'),
        ('Region VII', 'VII', 'CENTRAL VISAYAS'),
        ('Region VIII', 'VIII', 'EASTERN VISAYAS'),
        ('Region IX', 'IX', 'ZAMBOANGA PENINSULA'),
        ('Region X', 'X', 'NORTHERN MINDANAO'),
        ('Region XI', 'XI', 'DAVAO REGION'),
        ('Region XII', 'XII', 'SOCCSKSARGEN'),
        ('CARAGA', 'XIII', 'CARAGA'),
        ('BARMM', 'BARMM', 'BANGSAMORO AUTONOMOUS REGION IN MUSLIM MINDANAO'),
        ('Central Office', 'CO', 'CENTRAL OFFICE'),
        ('Nationwide', 'NW', 'NATIONWIDE')
    AS r(source_region, region_code, region_name)
)
SELECT
    p.year,
    r.region_code,
    r.region_name,
    p.location_type,
    p.category,
    CASE
        WHEN p.particulars IN (
            'The Presidential Communications Operations Office',
            'Presidential Communications Operations Office',
            'Office of the Press Secretary'
        ) THEN 'Presidential Communications Office (PCO)'
        WHEN p.particulars = 'Debt Service Fund-Interest Payment' THEN 'Debt Interest Payments'
        ELSE p.particulars
    END AS particulars,
    p.particulars AS particulars_as_stored,
    COALESCE(p.amount_thousand_php, 0) * 1000 AS obligations_amount_php,
    p.amount_status AS value_status,
    p.source_name,
    p.source_page
FROM regional_obligations_profile p
LEFT JOIN region_ref r
    ON p.regions = r.source_region
WHERE p.row_type = 'detail'
  AND p.location_type <> 'total';

-- 7.2 Silver readiness. Expected: 3,822 rows, 0 duplicates, 0 unmapped, 0 invalid amounts.
SELECT
    COUNT(*) AS silver_rows,
    COUNT(*) - COUNT(DISTINCT year, region_code, category, particulars) AS duplicate_business_keys,
    COUNT_IF(region_code IS NULL) AS unmapped_regions,
    COUNT_IF(value_status = 'invalid') AS invalid_amounts,
    COUNT_IF(value_status IN ('dash', 'blank')) AS amounts_set_to_zero,
    COUNT_IF(location_type = 'region') AS regional_rows,
    COUNT_IF(location_type IN ('central_office', 'nationwide')) AS non_regional_rows
FROM regional_obligations_silver_preview;

-- 7.3 Silver preview: total obligationss per region and year, in billion pesos
SELECT
    year,
    region_code,
    region_name,
    ROUND(SUM(obligations_amount_php) / 1e9, 1) AS obligationss_billion_php
FROM regional_obligations_silver_preview
GROUP BY year, region_code, region_name
ORDER BY year, region_code;


-- 8. OPTIONAL: INGESTION LINEAGE
-- Run only if the Bronze table has the pipeline columns (_source_file, _run_id, ...).
-- If DESCRIBE in 1.1 does not show them, skip this query.
SELECT
    _source_file,
    _run_id,
    COUNT(*) AS row_count,
    COUNT_IF(_rescued_data IS NOT NULL) AS rescued_rows,
    COUNT_IF(
        NULLIF(TRIM(_drive_file_id), '') IS NULL
        OR NULLIF(TRIM(_landing_file), '') IS NULL
        OR NULLIF(TRIM(_content_hash), '') IS NULL
        OR NULLIF(TRIM(_dataset_hash), '') IS NULL
        OR NULLIF(TRIM(_run_id), '') IS NULL
        OR _ingested_at IS NULL
    ) AS incomplete_lineage_rows,
    MIN(_ingested_at) AS earliest_ingestion,
    MAX(_ingested_at) AS latest_ingestion
FROM pondolens.dev_bronze.regional_obligations
GROUP BY _source_file, _run_id;
