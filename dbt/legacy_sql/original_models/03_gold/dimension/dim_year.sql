%sql
-- Creates the gold table for dim_year
CREATE OR REPLACE TABLE pondolens.dev_gold.dim_year
USING DELTA
AS
WITH all_years AS (
  -- Combine non-null years; UNION removes duplicates
  SELECT year FROM pondolens.dev_silver.regional_appropriations WHERE year IS NOT NULL
  UNION
  SELECT year FROM pondolens.dev_silver.regional_obligations WHERE year IS NOT NULL
  UNION
  SELECT year FROM pondolens.dev_silver.hospital WHERE year IS NOT NULL
  UNION
  SELECT year FROM pondolens.dev_silver.population WHERE year IS NOT NULL
  UNION
  SELECT year FROM pondolens.dev_silver.grdp_per_capita WHERE year IS NOT NULL
  UNION
  SELECT year FROM pondolens.dev_silver.unemployment_rate WHERE year IS NOT NULL
  UNION
  SELECT year FROM pondolens.dev_silver.poverty_incidence WHERE year IS NOT NULL
  UNION
  SELECT year FROM pondolens.dev_silver.completion_rate WHERE year IS NOT NULL
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
FROM distinct_years;