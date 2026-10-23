CREATE OR REPLACE VIEW pondolens.dev_gold.budget_regional AS
WITH location_yearly AS (
    -- Appropriations across all categories, including NW and CO.
    SELECT
        y.year,
        l.location_code,
        UPPER(TRIM(l.geographic_level)) AS geographic_level,
        SUM(fe.appropriation_amount) AS total_appropriation_php
    FROM pondolens.dev_gold.fact_regional_expenditure fe
    INNER JOIN pondolens.dev_gold.dim_year y
        ON fe.year_id = y.year_id
    INNER JOIN pondolens.dev_gold.dim_particular p
        ON fe.particular_id = p.particular_id
    INNER JOIN pondolens.dev_gold.dim_location l
        ON fe.location_id = l.location_id
    WHERE y.year BETWEEN 2021 AND 2025
      AND (
          UPPER(TRIM(l.geographic_level)) = 'REGION'
          OR UPPER(TRIM(l.location_code)) IN (
              'NW', 'CO', 'NATIONWIDE', 'CENTRAL OFFICE'
          )
      )
      AND UPPER(TRIM(p.particular)) NOT IN (
          '', 'ALL', 'TOTAL', 'GRAND TOTAL'
      )
    GROUP BY
        y.year,
        l.location_code,
        UPPER(TRIM(l.geographic_level))
),

yearly_totals AS (
    -- Denominator includes regions, Nationwide and Central Office.
    SELECT
        year,
        SUM(total_appropriation_php) AS yearly_total_including_nw_co_php
    FROM location_yearly
    GROUP BY year
)

SELECT
    ly.year,
    ly.location_code AS region,
    ly.total_appropriation_php,
    yt.yearly_total_including_nw_co_php,
    ROUND(
        100.0 * ly.total_appropriation_php
        / NULLIF(yt.yearly_total_including_nw_co_php, 0),
        4
    ) AS percentage_share
FROM location_yearly ly
INNER JOIN yearly_totals yt
    ON ly.year = yt.year
WHERE ly.geographic_level = 'REGION'
  AND UPPER(TRIM(ly.location_code)) NOT IN (
      'NW', 'CO', 'NATIONWIDE', 'CENTRAL OFFICE'
  )
  AND ly.total_appropriation_php IS NOT NULL;