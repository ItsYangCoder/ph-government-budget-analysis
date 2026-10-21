%sql
-- Creates the Delta table for dim_age_group using the current Silver population table
CREATE OR REPLACE TABLE pondolens.dev_gold.dim_age_group
USING DELTA
AS
WITH distinct_age_groups AS (
  -- Keep distinct age groups with their matching age limits.
  SELECT DISTINCT
    age_group,
    age_min,
    age_max
  FROM pondolens.dev_silver.population
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
FROM distinct_age_groups;