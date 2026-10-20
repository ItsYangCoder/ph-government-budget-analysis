%sql
-- Creates the gold table for fact_population
CREATE OR REPLACE TABLE pondolens.dev_gold.fact_population
USING DELTA
AS
WITH population_with_keys AS (
  -- Get the year, location, and age group surrogate keys from the other gold dim tables.
  SELECT
    y.year_id,
    l.location_id,
    a.age_group_id,
    p.population AS population_count
  FROM pondolens.dev_silver.population p
  INNER JOIN pondolens.dev_gold.dim_year y
    ON y.year = p.year
  INNER JOIN pondolens.dev_gold.dim_location l
    ON l.location_code = UPPER(TRIM(p.region_code))
  INNER JOIN pondolens.dev_gold.dim_age_group a
    ON a.age_group = p.age_group
  WHERE p.population IS NOT NULL
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
FROM population_with_keys;

-- Check population totals, locations, and age groups per year.
SELECT
  y.year,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT f.location_id) AS total_locations,
  COUNT(DISTINCT f.age_group_id) AS total_age_groups,
  SUM(f.population_count) AS total_population
FROM pondolens.dev_gold.fact_population f
INNER JOIN pondolens.dev_gold.dim_year y
  ON f.year_id = y.year_id
GROUP BY y.year
ORDER BY y.year;