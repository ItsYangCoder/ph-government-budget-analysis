WITH regions AS (
  SELECT location_id, location_code, location
  FROM pondolens.dev_gold.dim_location
  WHERE geographic_level = 'region'
),
obligations AS (
  SELECT f.year_id, f.location_id, SUM(f.obligation_amount) AS obligations_php
  FROM pondolens.dev_gold.fact_regional_expenditure f
  JOIN regions r ON f.location_id = r.location_id
  JOIN pondolens.dev_gold.dim_particular p ON f.particular_id = p.particular_id
  WHERE p.category <> 'UNKNOWN'
  -- AND p.category = 'DEPARTMENTS'
  GROUP BY f.year_id, f.location_id
),
population AS (
  SELECT fp.year_id, fp.location_id, fp.population_count AS population
  FROM pondolens.dev_gold.fact_population fp
  JOIN regions r ON fp.location_id = r.location_id
  JOIN pondolens.dev_gold.dim_age_group a ON fp.age_group_id = a.age_group_id
  WHERE a.age_min IS NULL AND a.age_max IS NULL
),
per_region AS (
  SELECT r.location_code, r.location AS region, y.year,
         o.obligations_php, pop.population,
         o.obligations_php / pop.population AS per_resident
  FROM obligations o
  JOIN population pop ON o.location_id = pop.location_id AND o.year_id = pop.year_id
  JOIN regions r ON o.location_id = r.location_id
  JOIN pondolens.dev_gold.dim_year y ON o.year_id = y.year_id
),
national AS (
  SELECT year, SUM(obligations_php) / SUM(population) AS national_per_resident
  FROM per_region
  GROUP BY year
)
SELECT
  pr.location_code,
  pr.region,
  pr.year,
  pr.population,
  ROUND(pr.per_resident, 0)                                 AS per_resident,
  ROUND(n.national_per_resident, 0)                         AS national_per_resident,
  ROUND(pr.per_resident / n.national_per_resident * 100, 0) AS per_100_national,
  ROUND(pr.per_resident / n.national_per_resident * 100, 0) - 100 AS diff_from_100,
  CASE WHEN pr.per_resident >= n.national_per_resident
       THEN 'Above national average' ELSE 'Below national average' END AS vs_national
FROM per_region pr
JOIN national n ON pr.year = n.year;

