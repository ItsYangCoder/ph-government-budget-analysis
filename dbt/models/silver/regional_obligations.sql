{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- Regional Obligations Silver
-- Source: {{ source('bronze', 'regional_obligations') }} (DBM BESF Table B.6.a, Actual Obligations, 2021-2025)
-- Target: {{ this }}
-- Grain: one row per year + category + particular + region_code (detail rows only, no totals).
-- IDs start at 2,000,001 and stay the same on rerun. Run with max 1 concurrent job.
-- Works on an existing table: missing columns are added and old agency names are renamed in place, so IDs are kept.

CREATE SCHEMA IF NOT EXISTS {{ this.database }}.{{ this.schema }}
-- pondolens:statement --
CREATE TABLE IF NOT EXISTS {{ this }} (
    obligation_id INT NOT NULL,
    year INT NOT NULL,
    category STRING NOT NULL,
    particular STRING,
    region_code STRING NOT NULL,
    region_name STRING NOT NULL,
    location_type STRING,
    expenditure_amount DECIMAL(20, 2) COMMENT 'Pesos',
    value_status STRING,
    particular_as_stored STRING,
    source_name STRING,
    source_page INT,
    processing_run_id STRING NOT NULL,
    processed_at TIMESTAMP NOT NULL,
    CONSTRAINT regional_obligations_pk PRIMARY KEY (obligation_id)
)
USING DELTA
COMMENT 'Regional expenditure obligations (actual obligations) in pesos. Grain: year, category, particular, region_code.'
-- pondolens:statement --
-- Add the new columns to an older table. No-op when they already exist.
DECLARE OR REPLACE VARIABLE regional_obligations_ddl STRING
-- pondolens:statement --
SET VAR regional_obligations_ddl = (
    SELECT CASE
        WHEN SIZE(missing) = 0 THEN 'SELECT 1'
        ELSE CONCAT('ALTER TABLE {{ this }} ADD COLUMNS (',
                    CONCAT_WS(', ', missing), ')')
    END
    FROM (
        SELECT FILTER(
            ARRAY(
                IF(ARRAY_CONTAINS(cols, 'location_type'), NULL, 'location_type STRING'),
                IF(ARRAY_CONTAINS(cols, 'value_status'), NULL, 'value_status STRING'),
                IF(ARRAY_CONTAINS(cols, 'particular_as_stored'), NULL, 'particular_as_stored STRING'),
                IF(ARRAY_CONTAINS(cols, 'source_name'), NULL, 'source_name STRING'),
                IF(ARRAY_CONTAINS(cols, 'source_page'), NULL, 'source_page INT')
            ),
            x -> x IS NOT NULL
        ) AS missing
        FROM (
            SELECT COLLECT_LIST(column_name) AS cols
            FROM {{ this.database }}.information_schema.columns
            WHERE table_schema = '{{ this.schema }}'
              AND table_name = 'regional_obligations'
        )
    )
)
-- pondolens:statement --
EXECUTE IMMEDIATE regional_obligations_ddl
-- pondolens:statement --
-- Run metadata.
DECLARE OR REPLACE VARIABLE v_run_id STRING
-- pondolens:statement --
DECLARE OR REPLACE VARIABLE v_run_ts TIMESTAMP
-- pondolens:statement --
SET VAR v_run_id = REPLACE(UUID(), '-', ''), v_run_ts = CURRENT_TIMESTAMP()
-- pondolens:statement --
-- Agency names that changed across years: one standard name per office.
CREATE OR REPLACE TEMP VIEW regional_obligation_particular_map AS
SELECT * FROM VALUES
    ('The Presidential Communications Operations Office', 'Presidential Communications Office (PCO)'),
    ('Presidential Communications Operations Office', 'Presidential Communications Office (PCO)'),
    ('Office of the Press Secretary', 'Presidential Communications Office (PCO)'),
    ('Debt Service Fund-Interest Payment', 'Debt Interest Payments')
AS m(source_particular, standard_particular)
-- pondolens:statement --
-- Crosswalk aliases with their validity years.
-- Includes regions plus CO (Central Office) and NW (Nationwide). PHL and Total are not needed here.
CREATE OR REPLACE TEMP VIEW regional_obligation_region_aliases AS
WITH crosswalk AS (
    SELECT
        UPPER(TRIM(source_region)) AS source_region,
        UPPER(TRIM(region_code)) AS region_code,
        MAX(UPPER(TRIM(region_name))) OVER (PARTITION BY UPPER(TRIM(region_code))) AS region_name,
        valid_from_year,
        valid_to_year
    FROM {{ ref('shared_region_crosswalk') }}
    WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
      AND NULLIF(TRIM(region_name), '') IS NOT NULL
      AND UPPER(TRIM(region_code)) <> 'PHL'
      AND (LOWER(TRIM(geographic_level)) = 'region'
           OR geographic_level IS NULL
           OR UPPER(TRIM(region_code)) IN ('CO', 'NW'))
      AND (valid_from_year IS NULL OR valid_to_year IS NULL OR valid_from_year <= valid_to_year)
),
aliases AS (
    SELECT
        region_code,
        region_name,
        valid_from_year,
        valid_to_year,
        EXPLODE(ARRAY_COMPACT(ARRAY(
            source_region,
            region_code,
            region_name,
            CONCAT('REGION ', region_code),
            CASE WHEN region_code = 'IVB' THEN 'MIMAROPA' END,
            CASE WHEN region_code = 'IVB' THEN 'MIMAROPA REGION' END
        ))) AS region_alias
    FROM crosswalk
)
SELECT DISTINCT
    REGEXP_REPLACE(region_alias, r'[^A-Z0-9]', '') AS alias_key,
    region_code,
    region_name,
    valid_from_year,
    valid_to_year
FROM aliases
WHERE REGEXP_REPLACE(region_alias, r'[^A-Z0-9]', '') <> ''
-- pondolens:statement --
-- Clean Bronze: detail rows only, latest ingestion per key, standard agency names.
-- Total column, 'All' subtotals and GRAND TOTAL are dropped. They can be recalculated with SUM.
CREATE OR REPLACE TEMP VIEW regional_obligation_bronze_clean AS
WITH trimmed AS (
    SELECT
        TRY_CAST(TRIM(CAST(year AS STRING)) AS INT) AS year,
        NULLIF(UPPER(REGEXP_REPLACE(TRIM(category), r'\s+', ' ')), '') AS category,
        NULLIF(REGEXP_REPLACE(TRIM(particulars), r'\s+', ' '), '') AS particular_as_stored,
        NULLIF(TRIM(regions), '') AS region_raw,
        NULLIF(REGEXP_REPLACE(UPPER(TRIM(regions)), r'[^A-Z0-9]', ''), '') AS region_key,
        LOWER(TRIM(price_basis)) AS price_basis,
        LOWER(TRIM(unit_amount)) AS unit_amount,
        NULLIF(REPLACE(TRIM(CAST(expenditure_amount AS STRING)), ',', ''), '') AS amount_txt,
        TRIM(source_name) AS source_name,
        TRY_CAST(TRIM(CAST(source_page AS STRING)) AS INT) AS source_page,
        _ingested_at
    FROM {{ source('bronze', 'regional_obligations') }}
),
detail AS (
    SELECT *
    FROM trimmed
    WHERE NOT (region_key <=> 'TOTAL')
      AND NOT (UPPER(particular_as_stored) <=> 'ALL')
      AND NOT (category <=> 'GRAND TOTAL')
),
latest AS (
    -- Latest ingestion per key. RANK keeps ties so conflicting values are caught by the duplicate check.
    SELECT *
    FROM detail
    QUALIFY RANK() OVER (
        PARTITION BY year, category, particular_as_stored, region_key
        ORDER BY _ingested_at DESC
    ) = 1
)
SELECT
    l.* EXCEPT (_ingested_at),
    COALESCE(m.standard_particular, l.particular_as_stored) AS particular,
    -- Dash and blank both mean no amount. Totals reconcile when they are treated as 0.
    CASE
        WHEN amount_txt IS NULL THEN 'blank'
        WHEN amount_txt IN ('-', '–', '—') THEN 'dash'
        WHEN TRY_CAST(amount_txt AS DECIMAL(20, 2)) IS NULL THEN 'invalid'
        ELSE 'numeric'
    END AS value_status,
    CASE
        WHEN amount_txt IS NULL OR amount_txt IN ('-', '–', '—') THEN CAST(0 AS DECIMAL(20, 2))
        WHEN unit_amount = 'thousand pesos' THEN CAST(TRY_CAST(amount_txt AS DECIMAL(20, 2)) * 1000 AS DECIMAL(20, 2))
        WHEN unit_amount = 'pesos' THEN TRY_CAST(amount_txt AS DECIMAL(20, 2))
    END AS expenditure_amount
FROM latest AS l
LEFT JOIN regional_obligation_particular_map AS m
    ON l.particular_as_stored = m.source_particular
-- pondolens:statement --
-- Map each row to one region valid for its year. Prefer an exact source_region alias.
CREATE OR REPLACE TEMP VIEW regional_obligation_mapping_candidates AS
SELECT
    c.*,
    a.region_code,
    a.region_name,
    DENSE_RANK() OVER (
        PARTITION BY c.year, c.category, c.particular_as_stored, c.region_key
        ORDER BY CASE WHEN a.alias_key = c.region_key THEN 1 ELSE 2 END
    ) AS match_rank
FROM regional_obligation_bronze_clean AS c
LEFT JOIN regional_obligation_region_aliases AS a
    ON c.region_key = a.alias_key
   AND c.year BETWEEN COALESCE(a.valid_from_year, 1900) AND COALESCE(a.valid_to_year, 9999)
-- pondolens:statement --
-- Do not choose between conflicting best matches.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Ambiguous region mapping: one region label matches two codes. Review shared_region_crosswalk.'
)
FROM (
    SELECT year, category, particular_as_stored, region_key
    FROM regional_obligation_mapping_candidates
    WHERE match_rank = 1 AND region_code IS NOT NULL
    GROUP BY year, category, particular_as_stored, region_key
    HAVING COUNT(DISTINCT region_code) > 1
) AS ambiguous
-- pondolens:statement --
-- Dataset-only backup mapping for the labels in Table B.6.a.
-- Used only when the crosswalk has no match for that label and year. The shared crosswalk is not changed.
CREATE OR REPLACE TEMP VIEW regional_obligation_region_fallback AS
SELECT
    REGEXP_REPLACE(UPPER(source_label), r'[^A-Z0-9]', '') AS alias_key,
    region_code,
    region_name
FROM VALUES
    ('Nationwide', 'NW', 'NATIONWIDE'),
    ('Central Office', 'CO', 'CENTRAL OFFICE'),
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
AS f(source_label, region_code, region_name)
-- pondolens:statement --
-- Region names come from the crosswalk when the code exists there, so both sources use the same name.
CREATE OR REPLACE TEMP VIEW regional_obligation_mapped AS
WITH best AS (
    SELECT DISTINCT * EXCEPT (match_rank)
    FROM regional_obligation_mapping_candidates
    WHERE match_rank = 1
),
crosswalk_names AS (
    SELECT region_code, MAX(region_name) AS region_name
    FROM regional_obligation_region_aliases
    GROUP BY region_code
),
resolved AS (
    SELECT
        b.* EXCEPT (region_code, region_name),
        COALESCE(b.region_code, f.region_code) AS region_code,
        COALESCE(b.region_name, n.region_name, f.region_name) AS region_name
    FROM best AS b
    LEFT JOIN regional_obligation_region_fallback AS f
        ON b.region_code IS NULL
       AND b.region_key = f.alias_key
    LEFT JOIN crosswalk_names AS n
        ON f.region_code = n.region_code
)
SELECT
    *,
    CASE
        WHEN region_code = 'CO' THEN 'central_office'
        WHEN region_code = 'NW' THEN 'nationwide'
        WHEN region_code IS NOT NULL THEN 'region'
    END AS location_type
FROM resolved
-- pondolens:statement --
-- To see which labels needed the backup: SELECT * FROM regional_obligation_fallback_used.
CREATE OR REPLACE TEMP VIEW regional_obligation_fallback_used AS
SELECT b.region_raw, b.year, f.region_code, COUNT(*) AS row_count
FROM (
    SELECT * FROM regional_obligation_mapping_candidates
    WHERE match_rank = 1 AND region_code IS NULL
) AS b
INNER JOIN regional_obligation_region_fallback AS f
    ON b.region_key = f.alias_key
GROUP BY b.region_raw, b.year, f.region_code
-- pondolens:statement --
-- List Bronze rows that cannot be loaded and their reasons.
CREATE OR REPLACE TEMP VIEW regional_obligation_rejected AS
SELECT *
FROM (
    SELECT
        year,
        category,
        particular_as_stored,
        region_raw,
        amount_txt,
        source_name,
        source_page,
        CONCAT_WS(
            '; ',
            CASE WHEN region_raw IS NULL THEN 'missing region'
                 WHEN region_code IS NULL THEN 'unmapped region for this year' END,
            CASE WHEN year IS NULL OR year NOT BETWEEN 2000 AND 2100 THEN 'invalid year' END,
            CASE WHEN category IS NULL
                   OR category NOT IN ('DEPARTMENTS', 'SPECIAL PURPOSE FUNDS', 'AUTOMATIC APPROPRIATIONS')
                 THEN 'unexpected category' END,
            CASE WHEN particular_as_stored IS NULL THEN 'missing particular' END,
            CASE WHEN price_basis IS NULL OR price_basis <> 'actual obligations' THEN 'unexpected price_basis' END,
            CASE WHEN unit_amount IS NULL OR unit_amount NOT IN ('thousand pesos', 'pesos') THEN 'unknown unit' END,
            CASE WHEN value_status = 'invalid' THEN 'invalid amount' END,
            CASE WHEN expenditure_amount < 0 THEN 'negative amount' END
        ) AS rejection_reason
    FROM regional_obligation_mapped
) AS rejected
WHERE rejection_reason <> ''
-- pondolens:statement --
-- To inspect rejected rows: SELECT * FROM regional_obligation_rejected.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Rejected Bronze rows found (region, year, category, unit or amount). See regional_obligation_rejected.'
)
FROM regional_obligation_rejected
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW regional_obligation_stage AS
SELECT
    year,
    category,
    particular,
    region_code,
    region_name,
    location_type,
    expenditure_amount,
    value_status,
    particular_as_stored,
    source_name,
    source_page
FROM regional_obligation_mapped
-- pondolens:statement --
-- Mapping must keep every detail Bronze row exactly once.
SELECT ASSERT_TRUE(
    (SELECT COUNT(*) FROM regional_obligation_stage)
        = (SELECT COUNT(*) FROM regional_obligation_bronze_clean),
    'Region mapping changed the regional obligation row count.'
)
-- pondolens:statement --
-- Stop if different Bronze labels produce the same Silver key.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Duplicate year/category/particular/region_code keys found in regional_obligation_stage.'
)
FROM (
    SELECT year, category, particular, region_code
    FROM regional_obligation_stage
    GROUP BY year, category, particular, region_code
    HAVING COUNT(*) > 1
) AS duplicate_stage_keys
-- pondolens:statement --
-- Older versions kept 'All' subtotal and GRAND TOTAL rows. Remove them (no-op afterwards).
DELETE FROM {{ this }}
WHERE UPPER(particular) = 'ALL'
   OR UPPER(category) = 'GRAND TOTAL'
   OR region_code = 'TOTAL'
-- pondolens:statement --
-- Rename old agency names already in Silver, so those rows keep their IDs.
-- Stop first if a rename would collide with a row that already has the standard name.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Renaming an old agency name would create a duplicate Silver key.'
)
FROM {{ this }} AS t
INNER JOIN regional_obligation_particular_map AS m
    ON t.particular = m.source_particular
INNER JOIN {{ this }} AS t2
    ON t2.year = t.year
    AND t2.category = t.category
    AND t2.region_code = t.region_code
    AND t2.particular = m.standard_particular
-- pondolens:statement --
MERGE INTO {{ this }} AS t
USING regional_obligation_particular_map AS m
ON t.particular = m.source_particular
WHEN MATCHED THEN UPDATE SET
    t.particular = m.standard_particular,
    t.particular_as_stored = m.source_particular,
    t.processing_run_id = v_run_id,
    t.processed_at = v_run_ts
-- pondolens:statement --
-- Check existing IDs and keys before merging.
SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT obligation_id)
    AND COUNT(*) = COUNT(DISTINCT STRUCT(year, category, particular, region_code))
    AND COUNT_IF(obligation_id <= 2000000) = 0,
    'Silver has duplicate IDs, duplicate keys or IDs at or below 2000000.'
)
FROM {{ this }}
-- pondolens:statement --
-- Stop if a Bronze year contains under 80% of its existing Silver rows.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'A Bronze year has under 80% of the Silver rows; possible partial load.'
)
FROM (
    SELECT t.year
    FROM {{ this }} AS t
    INNER JOIN (
        SELECT year, COUNT(*) AS n
        FROM regional_obligation_stage
        GROUP BY year
    ) AS s
        ON t.year = s.year
    GROUP BY t.year, s.n
    HAVING s.n < 0.8 * COUNT(*)
) AS partial_loads
-- pondolens:statement --
-- Only new keys receive a new ID. Start at 2000001 or continue from the highest ID.
CREATE OR REPLACE TEMP VIEW regional_obligation_numbered AS
WITH new_records AS (
    SELECT s.*
    FROM regional_obligation_stage AS s
    LEFT ANTI JOIN {{ this }} AS t
        ON s.year = t.year
        AND s.category = t.category
        AND s.particular = t.particular
        AND s.region_code = t.region_code
),
last_id AS (
    SELECT COALESCE(MAX(CAST(obligation_id AS BIGINT)), 2000000) AS last_number
    FROM {{ this }}
)
SELECT
    s.*,
    l.last_number + ROW_NUMBER() OVER (
        ORDER BY s.year, s.category, s.particular, s.region_code
    ) AS next_id
FROM new_records AS s
CROSS JOIN last_id AS l
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'New IDs must be between 2000001 and 2147483647.'
)
FROM regional_obligation_numbered
WHERE next_id NOT BETWEEN 2000001 AND 2147483647
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW regional_obligation_merge_source AS

-- Existing keys keep their IDs.
SELECT t.obligation_id, s.*, FALSE AS removed
FROM regional_obligation_stage AS s
INNER JOIN {{ this }} AS t
    ON s.year = t.year
    AND s.category = t.category
    AND s.particular = t.particular
    AND s.region_code = t.region_code

UNION ALL

-- New keys get the next IDs.
SELECT CAST(n.next_id AS INT), n.* EXCEPT (next_id), FALSE AS removed
FROM regional_obligation_numbered AS n

UNION ALL

-- Remove Silver rows missing from Bronze for years in this load.
SELECT
    t.obligation_id,
    t.year, t.category, t.particular, t.region_code, t.region_name, t.location_type,
    t.expenditure_amount, t.value_status, t.particular_as_stored, t.source_name, t.source_page,
    TRUE AS removed
FROM {{ this }} AS t
LEFT SEMI JOIN (SELECT DISTINCT year FROM regional_obligation_stage) AS y
    ON t.year = y.year
LEFT ANTI JOIN regional_obligation_stage AS s
    ON t.year = s.year
    AND t.category = s.category
    AND t.particular = s.particular
    AND t.region_code = s.region_code
-- pondolens:statement --
-- Stop if more than 10% of the Silver rows in this load's years would be deleted.
SELECT ASSERT_TRUE(
    (SELECT COUNT_IF(removed) FROM regional_obligation_merge_source)
        <= 0.10 * (SELECT COUNT(*) FROM {{ this }}
                   WHERE year IN (SELECT year FROM regional_obligation_stage)),
    'More than 10% of in-scope Silver rows would be deleted. Check that Bronze is complete.'
)
-- pondolens:statement --
MERGE INTO {{ this }} AS t
USING regional_obligation_merge_source AS s
ON t.obligation_id = s.obligation_id

WHEN MATCHED AND s.removed
THEN DELETE

WHEN MATCHED AND NOT s.removed AND NOT (
    t.region_name <=> s.region_name
    AND t.location_type <=> s.location_type
    AND t.expenditure_amount <=> s.expenditure_amount
    AND t.value_status <=> s.value_status
    AND t.particular_as_stored <=> s.particular_as_stored
    AND t.source_name <=> s.source_name
    AND t.source_page <=> s.source_page
)
THEN UPDATE SET
    t.region_name = s.region_name,
    t.location_type = s.location_type,
    t.expenditure_amount = s.expenditure_amount,
    t.value_status = s.value_status,
    t.particular_as_stored = s.particular_as_stored,
    t.source_name = s.source_name,
    t.source_page = s.source_page,
    t.processing_run_id = v_run_id,
    t.processed_at = v_run_ts

WHEN NOT MATCHED AND NOT s.removed
THEN INSERT (
    obligation_id, year, category, particular, region_code, region_name, location_type,
    expenditure_amount, value_status, particular_as_stored, source_name, source_page,
    processing_run_id, processed_at
)
VALUES (
    s.obligation_id, s.year, s.category, s.particular, s.region_code, s.region_name, s.location_type,
    s.expenditure_amount, s.value_status, s.particular_as_stored, s.source_name, s.source_page,
    v_run_id, v_run_ts
)
-- pondolens:statement --
-- Final check. Expected: 3,822 rows (741, 760, 760, 741, 820 per year),
-- 19 location codes per year (20 in 2025 with NIR), 1,333 rows with no amount,
-- totals 4.601 / 5.175 / 5.473 / 6.273 / 6.393 trillion pesos (same as the PDF grand totals).
SELECT
    year,
    COUNT(*) AS silver_rows,
    COUNT(DISTINCT region_code) AS location_codes,
    COUNT_IF(location_type = 'region') AS regional_rows,
    COUNT_IF(location_type IN ('central_office', 'nationwide')) AS non_regional_rows,
    COUNT_IF(value_status IN ('dash', 'blank')) AS no_amount_rows,
    ROUND(SUM(expenditure_amount) / 1e12, 3) AS total_trillion_php,
    MIN(obligation_id) AS first_id,
    MAX(obligation_id) AS last_id
FROM {{ this }}
GROUP BY year
ORDER BY year
