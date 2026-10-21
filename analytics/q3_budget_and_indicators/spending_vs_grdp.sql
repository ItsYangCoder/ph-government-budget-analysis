%sql

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
