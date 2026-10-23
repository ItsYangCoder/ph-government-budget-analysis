CREATE OR REPLACE VIEW pondolens.dev_gold.analytics_dpwh_regional_budget AS
WITH dpwh_regional AS (
  SELECT
    dy.year,
    dl.location AS region,
    SUM(fe.appropriation_amount) AS total_appropriation_php,
    SUM(fe.obligation_amount) AS total_obligation_php
  FROM pondolens.dev_gold.fact_regional_expenditure fe
  JOIN pondolens.dev_gold.dim_particular dp
    ON fe.particular_id = dp.particular_id
  JOIN pondolens.dev_gold.dim_location dl
    ON fe.location_id = dl.location_id
  JOIN pondolens.dev_gold.dim_year dy
    ON fe.year_id = dy.year_id
  WHERE dp.particular = 'DEPARTMENT OF PUBLIC WORKS AND HIGHWAYS (DPWH)'
    AND dl.geographic_level = 'region'
    AND fe.obligation_amount IS NOT NULL
  GROUP BY dy.year, dl.location
)
SELECT
  year,
  region,
  total_appropriation_php,
  total_obligation_php,
  RANK() OVER (
    PARTITION BY year
    ORDER BY total_obligation_php DESC
  ) AS budget_rank
FROM dpwh_regional
ORDER BY year, budget_rank;