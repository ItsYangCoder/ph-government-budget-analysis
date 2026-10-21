-- Run after dbt Gold builds. Both objects below are ordinary SQL views.
-- Population uses the current non-overlapping age-group detail, excluding all-age totals.
CREATE OR REPLACE VIEW pondolens.dev_gold.mv_grdp_spending_population AS
WITH population AS (
    SELECT f.year_id, f.location_id, SUM(f.population_count) AS total_population
    FROM pondolens.dev_gold.fact_population f
    JOIN pondolens.dev_gold.dim_age_group a ON f.age_group_id = a.age_group_id
    WHERE a.age_min IS NOT NULL
    GROUP BY f.year_id, f.location_id
    HAVING COUNT(*) = COUNT(f.population_count) AND SUM(f.population_count) > 0
), obligations AS (
    SELECT f.year_id, f.location_id, SUM(f.obligation_amount) AS total_obligations
    FROM pondolens.dev_gold.fact_regional_expenditure f
    JOIN pondolens.dev_gold.dim_particular p ON f.particular_id = p.particular_id
    WHERE p.category <> 'UNKNOWN' AND f.obligation_amount IS NOT NULL
    GROUP BY f.year_id, f.location_id
), grdp AS (
    SELECT f.year_id, f.location_id, f.measurement AS grdp_per_capita_php
    FROM pondolens.dev_gold.fact_regional_indicator f
    JOIN pondolens.dev_gold.dim_indicator d ON f.indicator_id = d.indicator_id
    WHERE d.indicator = 'grdp_per_capita'
      AND d.measure_type = 'grdp_per_capita_constant_2018_prices'
      AND d.unit = 'PHP/person (2018 prices)'
      AND f.measurement IS NOT NULL
)
SELECT y.year, l.location_id, l.location_code AS region_code,
       l.location AS region_name, g.grdp_per_capita_php,
       TRY_DIVIDE(o.total_obligations, p.total_population) AS obligations_per_resident_php,
       p.total_population, o.total_obligations
FROM grdp g
JOIN population p ON g.year_id = p.year_id AND g.location_id = p.location_id
JOIN obligations o ON g.year_id = o.year_id AND g.location_id = o.location_id
JOIN pondolens.dev_gold.dim_year y ON g.year_id = y.year_id
JOIN pondolens.dev_gold.dim_location l ON g.location_id = l.location_id
WHERE l.geographic_level = 'region' AND y.year BETWEEN 2021 AND 2025;


-- AP3: GRDP vs Obligations per Capita
-- Four-quadrant scatter plot using actual values
-- Median reference lines calculated per year
-- NCR excluded

CREATE OR REPLACE VIEW pondolens.dev_gold.mv_grdp_spending_population_without_ncr
AS
WITH regional_data AS (
    SELECT
        year,
        location_id,
        region_code,
        region_name,
        grdp_per_capita_php,
        obligations_per_resident_php,
        total_population,
        total_obligations

    FROM pondolens.dev_gold.mv_grdp_spending_population

    WHERE UPPER(TRIM(region_code)) <> 'NCR'
      AND grdp_per_capita_php IS NOT NULL
      AND obligations_per_resident_php IS NOT NULL
      AND grdp_per_capita_php >= 0
      AND obligations_per_resident_php >= 0
      AND total_population > 0
),

yearly_medians AS (
    SELECT
        year,

        PERCENTILE_APPROX(
            grdp_per_capita_php,
            0.5,
            10000
        ) AS median_grdp,

        PERCENTILE_APPROX(
            obligations_per_resident_php,
            0.5,
            10000
        ) AS median_obligations

    FROM regional_data
    GROUP BY year
)

SELECT
    r.year,
    r.location_id,
    r.region_code,
    r.region_name,

    -- Actual values for scatter plot axes
    r.grdp_per_capita_php,
    r.obligations_per_resident_php,

    -- Supporting measures
    r.total_population,
    r.total_obligations,

    -- Median reference values
    ROUND(m.median_grdp, 2) AS median_grdp,
    ROUND(m.median_obligations, 2) AS median_obligations,

    -- Quadrant classification
    CASE
        WHEN r.grdp_per_capita_php >= m.median_grdp
         AND r.obligations_per_resident_php >= m.median_obligations
            THEN 'Q1 - High GRDP, High Obligations'

        WHEN r.grdp_per_capita_php < m.median_grdp
         AND r.obligations_per_resident_php >= m.median_obligations
            THEN 'Q2 - Low GRDP, High Obligations'

        WHEN r.grdp_per_capita_php < m.median_grdp
         AND r.obligations_per_resident_php < m.median_obligations
            THEN 'Q3 - Low GRDP, Low Obligations'

        ELSE 'Q4 - High GRDP, Low Obligations'
    END AS quadrant

FROM regional_data r
INNER JOIN yearly_medians m
    ON r.year = m.year

ORDER BY r.year DESC, r.region_code;
