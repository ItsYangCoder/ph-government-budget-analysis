{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}
CREATE OR REPLACE TEMP VIEW dbt_dim_year_candidate AS
WITH all_years AS (
  -- Combine non-null years; UNION removes duplicates
  SELECT year FROM {{ ref('regional_appropriations') }} WHERE year IS NOT NULL
  UNION
  SELECT year FROM {{ ref('regional_obligations') }} WHERE year IS NOT NULL
  UNION
  SELECT year FROM {{ ref('hospital') }} WHERE year IS NOT NULL
  UNION
  SELECT year FROM {{ ref('population') }} WHERE year IS NOT NULL
  UNION
  SELECT year FROM {{ ref('grdp_per_capita') }} WHERE year IS NOT NULL
  UNION
  SELECT year FROM {{ ref('unemployment_rate') }} WHERE year IS NOT NULL
  UNION
  SELECT year FROM {{ ref('poverty_incidence') }} WHERE year IS NOT NULL
  UNION
  SELECT year FROM {{ ref('completion_rate') }} WHERE year IS NOT NULL
),
distinct_years AS (
  SELECT DISTINCT CAST(year AS INT) AS year
  FROM all_years
)
SELECT
  -- Assign unique IDs starting at 20000, ordered by year
  CAST(
    19999 + ROW_NUMBER() OVER (ORDER BY year)
    AS INT
  ) AS year_id,
  year
FROM distinct_years
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty dim_year source') FROM dbt_dim_year_candidate
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate dim_year source grain') FROM (SELECT year FROM dbt_dim_year_candidate GROUP BY year HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE TABLE IF NOT EXISTS {{ this }} USING DELTA AS SELECT * FROM dbt_dim_year_candidate WHERE 1 = 0
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT year_id) AND COUNT_IF(year_id IS NULL OR year_id < 20000) = 0, 'Invalid existing dim_year IDs') FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate existing dim_year grain') FROM (SELECT year FROM {{ this }} GROUP BY year HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW dbt_dim_year_mapped AS
WITH matches AS (SELECT s.*, t.year_id AS existing_id FROM dbt_dim_year_candidate s LEFT JOIN {{ this }} t ON t.year <=> s.year), last_id AS (SELECT GREATEST(COALESCE(MAX(CAST(year_id AS BIGINT)), 19999), 19999) AS last_id FROM {{ this }})
SELECT CAST(COALESCE(existing_id, last_id + ROW_NUMBER() OVER (PARTITION BY existing_id IS NULL ORDER BY year)) AS INT) AS year_id, m.year
FROM matches m CROSS JOIN last_id
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(year_id IS NULL) = 0, 'dim_year ID allocation overflow') FROM dbt_dim_year_mapped
-- pondolens:statement --
MERGE INTO {{ this }} t USING dbt_dim_year_mapped s ON t.year <=> s.year
WHEN NOT MATCHED THEN INSERT (year_id, year) VALUES (s.year_id, s.year)
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'dim_year differs from prepared source') FROM (SELECT year FROM dbt_dim_year_candidate EXCEPT ALL SELECT year FROM {{ this }})
