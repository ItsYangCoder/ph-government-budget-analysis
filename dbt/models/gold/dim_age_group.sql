{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}
CREATE OR REPLACE TEMP VIEW dbt_dim_age_group_candidate AS
WITH distinct_age_groups AS (
  -- Keep distinct age groups with their matching age limits.
  SELECT DISTINCT
    age_group,
    age_min,
    age_max
  FROM {{ ref('population') }}
  WHERE age_group IS NOT NULL
)
SELECT
  -- Recalculate IDs starting at 80000, ordered by age.
  CAST(
    79999 + ROW_NUMBER() OVER (
      ORDER BY age_min, age_group, age_max
    )
    AS INT
  ) AS age_group_id,
  age_group,
  age_min,
  age_max
FROM distinct_age_groups
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty dim_age_group source') FROM dbt_dim_age_group_candidate
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate dim_age_group source grain') FROM (SELECT age_group FROM dbt_dim_age_group_candidate GROUP BY age_group HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE TABLE IF NOT EXISTS {{ this }} USING DELTA AS SELECT *, CURRENT_TIMESTAMP() AS processed_at FROM dbt_dim_age_group_candidate WHERE 1 = 0
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT age_group_id) AND COUNT_IF(age_group_id IS NULL OR age_group_id < 80000) = 0, 'Invalid existing dim_age_group IDs') FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate existing dim_age_group grain') FROM (SELECT age_group FROM {{ this }} GROUP BY age_group HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW dbt_dim_age_group_mapped AS
WITH matches AS (SELECT s.*, t.age_group_id AS existing_id FROM dbt_dim_age_group_candidate s LEFT JOIN {{ this }} t ON t.age_group <=> s.age_group), last_id AS (SELECT GREATEST(COALESCE(MAX(CAST(age_group_id AS BIGINT)), 79999), 79999) AS last_id FROM {{ this }})
SELECT CAST(COALESCE(existing_id, last_id + ROW_NUMBER() OVER (PARTITION BY existing_id IS NULL ORDER BY age_group)) AS INT) AS age_group_id, m.age_group, m.age_min, m.age_max
FROM matches m CROSS JOIN last_id
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(age_group_id IS NULL) = 0, 'dim_age_group ID allocation overflow') FROM dbt_dim_age_group_mapped
-- pondolens:statement --
MERGE INTO {{ this }} t USING dbt_dim_age_group_mapped s ON t.age_group <=> s.age_group
WHEN MATCHED AND (NOT (t.age_min <=> s.age_min) OR NOT (t.age_max <=> s.age_max)) THEN UPDATE SET t.age_min = s.age_min, t.age_max = s.age_max, t.processed_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (age_group_id, age_group, age_min, age_max, processed_at) VALUES (s.age_group_id, s.age_group, s.age_min, s.age_max, CURRENT_TIMESTAMP())
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'dim_age_group differs from prepared source') FROM (SELECT age_group, age_min, age_max FROM dbt_dim_age_group_candidate EXCEPT ALL SELECT age_group, age_min, age_max FROM {{ this }})
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(processed_at IS NULL) = 0, 'Missing dim_age_group processed_at') FROM {{ this }}
