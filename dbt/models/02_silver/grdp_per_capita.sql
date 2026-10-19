-- GRDP per capita | Silver | Project scope: 2021-2025
-- Execute in statement order in one session; stop on any failed assertion.
-- Configure one concurrent writer; keep Bronze and crosswalk stable during execution.
-- Geography: preserve this source's reported regional identities. This is not
-- historical boundary harmonization for budget joins. NIR history is retained
-- only for the explicitly identified source series below; review before Gold.

SET TIME ZONE 'UTC';
CREATE SCHEMA IF NOT EXISTS pondolens.dev_silver;

-- Validate year labels before filtering, so malformed years are not hidden.
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Malformed GRDP per capita year in Bronze.')
FROM pondolens.dev_bronze.grdp_per_capita
WHERE year IS NULL OR NOT (TRIM(year) RLIKE '^[0-9]{4}$');

CREATE OR REPLACE TEMP VIEW grdp_pc_source AS
SELECT
    TRY_CAST(TRIM(year) AS INT) AS year,
    NULLIF(REGEXP_REPLACE(UPPER(TRIM(region_id)), '[^A-Z0-9]', ''), '') AS code_key,
    NULLIF(REGEXP_REPLACE(UPPER(TRIM(region)), '[^A-Z0-9]', ''), '') AS name_key,
    TRY_CAST(REPLACE(TRIM(grdp_per_capita_amount), ',', '') AS DECIMAL(30,15)) AS parsed_amount,
    TRY_CAST(REPLACE(TRIM(grdp_per_capita_amount), ',', '') AS DECIMAL(20,6)) AS amount,
    LOWER(TRIM(price_basis)) AS source_basis,
    LOWER(TRIM(geographic_level)) AS source_level,
    LOWER(TRIM(unit)) AS unit,
    TRIM(source_name) AS source_name,
    _rescued_data
FROM pondolens.dev_bronze.grdp_per_capita
WHERE TRY_CAST(TRIM(year) AS INT) BETWEEN 2021 AND 2025;

SELECT ASSERT_TRUE(
    COUNT(*) > 0 AND COUNT_IF(
        name_key IS NULL OR parsed_amount IS NULL OR parsed_amount <= 0
        OR amount IS NULL OR amount <= 0
        OR source_basis IS NULL
        OR source_basis NOT IN ('at current prices', 'at constant 2018 prices')
        OR source_level IS NULL OR source_level NOT IN ('region', 'country')
        OR unit IS NULL OR unit <> 'philippine pesos per person'
        OR NULLIF(TRIM(_rescued_data), '') IS NOT NULL
    ) = 0,
    'Invalid GRDP per capita source values, units, geography or empty scope.'
)
FROM grdp_pc_source;

-- Shared canonical identity; PHL is national even if the lookup uses nationwide.
CREATE OR REPLACE TEMP VIEW grdp_pc_regions AS
SELECT DISTINCT
    UPPER(TRIM(region_code)) AS region_code,
    TRIM(region_name) AS region_name,
    CASE WHEN UPPER(TRIM(region_code)) = 'PHL' THEN 'national' ELSE 'region' END AS geographic_level
FROM pondolens.dev_silver.shared_region_crosswalk
WHERE NULLIF(TRIM(region_code), '') IS NOT NULL
  AND NULLIF(TRIM(region_name), '') IS NOT NULL
  AND UPPER(TRIM(region_code)) NOT IN ('CO', 'NW')
  AND (UPPER(TRIM(region_code)) = 'PHL' OR LOWER(TRIM(geographic_level)) = 'region');

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Conflicting canonical region names in crosswalk.')
FROM (
    SELECT region_code FROM grdp_pc_regions
    GROUP BY region_code HAVING COUNT(*) > 1
);

CREATE OR REPLACE TEMP VIEW grdp_pc_aliases AS
WITH labels AS (
    SELECT UPPER(TRIM(region_code)) AS region_code, source_region AS label
    FROM pondolens.dev_silver.shared_region_crosswalk
    UNION ALL
    SELECT region_code, region_name FROM grdp_pc_regions
    UNION ALL
    SELECT region_code, region_code FROM grdp_pc_regions
)
SELECT DISTINCT l.region_code,
    REGEXP_REPLACE(UPPER(TRIM(l.label)), '[^A-Z0-9]', '') AS alias_key
FROM labels l
WHERE NULLIF(TRIM(l.label), '') IS NOT NULL
  AND l.region_code IN (SELECT region_code FROM grdp_pc_regions);

SELECT ASSERT_TRUE(COUNT(*) = 0, 'Conflicting normalized GRDP per capita aliases.')
FROM (
    SELECT alias_key FROM grdp_pc_aliases
    GROUP BY alias_key HAVING COUNT(DISTINCT region_code) > 1
);

CREATE OR REPLACE TEMP VIEW grdp_pc_stage AS
WITH mapped AS (
    SELECT s.*, c.region_code AS code_match, n.region_code AS name_match,
        COALESCE(c.region_code, n.region_code) AS mapped_code
    FROM grdp_pc_source s
    LEFT JOIN grdp_pc_aliases c ON s.code_key = c.alias_key
    LEFT JOIN grdp_pc_aliases n ON s.name_key = n.alias_key
)
SELECT m.year, r.region_code, r.region_name, r.geographic_level,
    m.amount AS grdp_per_capita,
    CASE WHEN source_basis = 'at constant 2018 prices' THEN 2018 ELSE m.year END AS price_basis,
    m.code_key, m.code_match, m.name_match, m.source_level, m.source_name
FROM mapped m
LEFT JOIN grdp_pc_regions r ON m.mapped_code = r.region_code;

SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'Unmapped or conflicting geography, or source code/name disagreement.'
)
FROM grdp_pc_stage
WHERE region_code IS NULL OR region_name IS NULL OR geographic_level IS NULL
   OR (code_key IS NOT NULL AND code_match IS NULL)
   OR (code_match IS NOT NULL AND name_match IS NOT NULL AND code_match <> name_match)
   OR (source_level = 'country' AND region_code <> 'PHL')
   OR (source_level = 'region' AND geographic_level <> 'region');

-- Require an applicable canonical-code interval. Historical NIR observations
-- are an explicit source-specific preservation exception, not a shared date edit.
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Region/year applicability needs review for this source.')
FROM grdp_pc_stage s
WHERE NOT EXISTS (
    SELECT 1 FROM pondolens.dev_silver.shared_region_crosswalk c
    WHERE UPPER(TRIM(c.region_code)) = s.region_code
      AND NULLIF(TRIM(c.region_name), '') IS NOT NULL
      AND (s.region_code = 'PHL' OR LOWER(TRIM(c.geographic_level)) = 'region')
      AND s.year BETWEEN COALESCE(c.valid_from_year, 1900) AND COALESCE(c.valid_to_year, 9999)
)
AND NOT (
    s.region_code = 'NIR' AND s.year BETWEEN 2021 AND 2023
    AND COALESCE(s.source_name, '') = '2018-2025 GRDP_Reg_(with NIR as of April 2026)'
);

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT STRUCT(year, region_code, price_basis, geographic_level))
    AND COUNT(*) = (SELECT COUNT(*) FROM grdp_pc_source),
    'Duplicate GRDP per capita keys or mapping changed source row count.'
)
FROM grdp_pc_stage;

CREATE TABLE IF NOT EXISTS pondolens.dev_silver.grdp_per_capita (
    grdp_per_capita_id BIGINT NOT NULL,
    region_code STRING NOT NULL,
    region_name STRING NOT NULL,
    year INT NOT NULL,
    grdp_per_capita DECIMAL(20,6) NOT NULL,
    price_basis INT NOT NULL,
    geographic_level STRING NOT NULL,
    processed_at TIMESTAMP NOT NULL
)
USING DELTA
COMMENT 'Source-reported economic output per person in Philippine pesos; regional boundaries require review before budget comparisons.';

-- Do not silently load decimals into an earlier BIGINT target.
SELECT ASSERT_TRUE(COUNT(*) = 1, 'Target amount must be DECIMAL(20,6); review existing schema.')
FROM pondolens.information_schema.columns
WHERE table_schema = 'dev_silver' AND table_name = 'grdp_per_capita'
  AND column_name = 'grdp_per_capita'
  AND UPPER(data_type) = 'DECIMAL' AND numeric_precision = 20 AND numeric_scale = 6;

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT grdp_per_capita_id)
    AND COUNT(*) = COUNT(DISTINCT STRUCT(year, region_code, price_basis, geographic_level))
    AND COALESCE(COUNT_IF(
        grdp_per_capita_id IS NULL OR grdp_per_capita_id < 100000001
        OR NULLIF(TRIM(region_code), '') IS NULL OR region_code <> UPPER(TRIM(region_code))
        OR NULLIF(TRIM(region_name), '') IS NULL OR year IS NULL
        OR price_basis IS NULL OR price_basis NOT IN (2018, year)
        OR geographic_level IS NULL OR geographic_level NOT IN ('national', 'region')
        OR (geographic_level = 'national' AND region_code <> 'PHL')
        OR (geographic_level = 'region' AND region_code = 'PHL')
        OR grdp_per_capita IS NULL OR grdp_per_capita <= 0 OR processed_at IS NULL
    ), 0) = 0,
    'Invalid existing target keys, IDs or values; review before refresh.'
)
FROM pondolens.dev_silver.grdp_per_capita;

CREATE OR REPLACE TEMP VIEW grdp_pc_new_ids AS
WITH new_keys AS (
    SELECT s.year, s.region_code, s.price_basis, s.geographic_level
    FROM grdp_pc_stage s
    LEFT ANTI JOIN pondolens.dev_silver.grdp_per_capita t
      ON s.year = t.year AND s.region_code = t.region_code
     AND s.price_basis = t.price_basis AND s.geographic_level = t.geographic_level
), maximum_id AS (
    SELECT COALESCE(MAX(grdp_per_capita_id), CAST(100000000 AS BIGINT)) AS last_id
    FROM pondolens.dev_silver.grdp_per_capita
)
SELECT k.*, TRY_ADD(m.last_id, ROW_NUMBER() OVER (
    ORDER BY k.year, k.region_code, k.price_basis, k.geographic_level
)) AS new_id
FROM new_keys k CROSS JOIN maximum_id m;

SELECT ASSERT_TRUE(COUNT(*) = 0, 'GRDP per capita ID allocation overflow.')
FROM grdp_pc_new_ids WHERE new_id IS NULL;

CREATE OR REPLACE TEMP VIEW grdp_pc_merge_source AS
SELECT s.year, s.region_code, s.region_name, s.price_basis, s.geographic_level,
    s.grdp_per_capita, n.new_id
FROM grdp_pc_stage s
LEFT JOIN grdp_pc_new_ids n
  ON s.year = n.year AND s.region_code = n.region_code
 AND s.price_basis = n.price_basis AND s.geographic_level = n.geographic_level;

MERGE INTO pondolens.dev_silver.grdp_per_capita AS t
USING grdp_pc_merge_source AS s
ON t.year = s.year AND t.region_code = s.region_code
AND t.price_basis = s.price_basis AND t.geographic_level = s.geographic_level
WHEN MATCHED AND NOT (
    t.region_name <=> s.region_name AND t.grdp_per_capita <=> s.grdp_per_capita
) THEN UPDATE SET
    t.region_name = s.region_name,
    t.grdp_per_capita = s.grdp_per_capita,
    t.processed_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (
    grdp_per_capita_id, region_code, region_name, year,
    grdp_per_capita, price_basis, geographic_level, processed_at
) VALUES (
    s.new_id, s.region_code, s.region_name, s.year,
    s.grdp_per_capita, s.price_basis, s.geographic_level, CURRENT_TIMESTAMP()
);

-- Reconcile current staged observations without treating retained history as extra.
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Target differs from current validated source.')
FROM grdp_pc_stage s
LEFT JOIN pondolens.dev_silver.grdp_per_capita t
  ON s.year = t.year AND s.region_code = t.region_code
 AND s.price_basis = t.price_basis AND s.geographic_level = t.geographic_level
WHERE t.grdp_per_capita_id IS NULL
   OR NOT (s.region_name <=> t.region_name)
   OR NOT (s.grdp_per_capita <=> t.grdp_per_capita);

SELECT COUNT(*) AS total_rows, COUNT(DISTINCT grdp_per_capita_id) AS unique_ids,
    MIN(grdp_per_capita_id) AS first_id, MAX(grdp_per_capita_id) AS last_id
FROM pondolens.dev_silver.grdp_per_capita;
SELECT year, price_basis, geographic_level, COUNT(*) AS row_count
FROM pondolens.dev_silver.grdp_per_capita
GROUP BY year, price_basis, geographic_level ORDER BY year, price_basis, geographic_level;
