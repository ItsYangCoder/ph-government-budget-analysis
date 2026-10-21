{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}
CREATE OR REPLACE TEMP VIEW dbt_fact_population_candidate AS
WITH population_with_keys AS (
  -- Get the year, location, and age group surrogate keys from the other gold dim tables.
  SELECT
    y.year_id,
    l.location_id,
    a.age_group_id,
    p.population AS population_count
  FROM {{ ref('population') }} p
  INNER JOIN {{ ref('dim_year') }} y
    ON y.year = p.year
  INNER JOIN {{ ref('dim_location') }} l
    ON l.location_code = UPPER(TRIM(p.region_code))
  INNER JOIN {{ ref('dim_age_group') }} a
    ON a.age_group = p.age_group
  WHERE p.population IS NOT NULL
    AND p.sex = 'Both'
)
SELECT
  -- Assign unique IDs starting at 90000, ordered by year, location, age group
  CAST(
    89999 + ROW_NUMBER() OVER (
      ORDER BY year_id, location_id, age_group_id
    )
    AS INT
  ) AS fact_population_id,
  year_id,
  location_id,
  age_group_id,
  population_count
FROM population_with_keys
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) > 0, 'Empty fact_population source') FROM dbt_fact_population_candidate
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate fact_population source grain') FROM (SELECT year_id, location_id, age_group_id FROM dbt_fact_population_candidate GROUP BY year_id, location_id, age_group_id HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE TABLE IF NOT EXISTS {{ this }} USING DELTA AS SELECT *, CURRENT_TIMESTAMP() AS processed_at FROM dbt_fact_population_candidate WHERE 1 = 0
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = COUNT(DISTINCT fact_population_id) AND COUNT_IF(fact_population_id IS NULL OR fact_population_id < 90000) = 0, 'Invalid existing fact_population IDs') FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'Duplicate existing fact_population grain') FROM (SELECT year_id, location_id, age_group_id FROM {{ this }} GROUP BY year_id, location_id, age_group_id HAVING COUNT(*) > 1)
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW dbt_fact_population_mapped AS
WITH matches AS (SELECT s.*, t.fact_population_id AS existing_id FROM dbt_fact_population_candidate s LEFT JOIN {{ this }} t ON t.year_id <=> s.year_id AND t.location_id <=> s.location_id AND t.age_group_id <=> s.age_group_id), last_id AS (SELECT GREATEST(COALESCE(MAX(CAST(fact_population_id AS BIGINT)), 89999), 89999) AS last_id FROM {{ this }})
SELECT CAST(COALESCE(existing_id, last_id + ROW_NUMBER() OVER (PARTITION BY existing_id IS NULL ORDER BY year_id, location_id, age_group_id)) AS INT) AS fact_population_id, m.year_id, m.location_id, m.age_group_id, m.population_count
FROM matches m CROSS JOIN last_id
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(fact_population_id IS NULL) = 0, 'fact_population ID allocation overflow') FROM dbt_fact_population_mapped
-- pondolens:statement --
MERGE INTO {{ this }} t USING dbt_fact_population_mapped s ON t.year_id <=> s.year_id AND t.location_id <=> s.location_id AND t.age_group_id <=> s.age_group_id
WHEN MATCHED AND (NOT (t.population_count <=> s.population_count)) THEN UPDATE SET t.population_count = s.population_count, t.processed_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT (fact_population_id, year_id, location_id, age_group_id, population_count, processed_at) VALUES (s.fact_population_id, s.year_id, s.location_id, s.age_group_id, s.population_count, CURRENT_TIMESTAMP())
WHEN NOT MATCHED BY SOURCE THEN DELETE
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT(*) = 0, 'fact_population differs from prepared source') FROM (SELECT year_id, location_id, age_group_id, population_count FROM dbt_fact_population_candidate EXCEPT ALL SELECT year_id, location_id, age_group_id, population_count FROM {{ this }})
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(processed_at IS NULL) = 0, 'Missing fact_population processed_at') FROM {{ this }}
