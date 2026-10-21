%sql

-- AP2: Population Share vs Spending Share
-- Includes spending per person (PHP)
-- Databricks SQL view

CREATE OR REPLACE VIEW
    pondolens.dev_gold.mv_population_spending_alignment
AS

WITH regional_population AS (
    SELECT
        fp.year_id,
        fp.location_id,
        SUM(fp.population_count) AS total_population
    FROM pondolens.dev_gold.fact_population fp
    INNER JOIN pondolens.dev_gold.dim_age_group dag
        ON fp.age_group_id = dag.age_group_id
    WHERE dag.age_min IS NOT NULL
    GROUP BY
        fp.year_id,
        fp.location_id
    HAVING COUNT(*) = (SELECT COUNT(*) FROM pondolens.dev_gold.dim_age_group WHERE age_min IS NOT NULL)
       AND COUNT(DISTINCT fp.age_group_id) = COUNT(*)
       AND COUNT(*) = COUNT(fp.population_count)
       AND MIN(fp.population_count) >= 0
       AND SUM(fp.population_count) > 0
),

regional_obligations AS (
    SELECT
        fe.year_id,
        fe.location_id,
        SUM(fe.obligation_amount) AS total_obligations
    FROM pondolens.dev_gold.fact_regional_expenditure fe
    WHERE fe.obligation_amount IS NOT NULL
    GROUP BY
        fe.year_id,
        fe.location_id
),

combined AS (
    SELECT
        dy.year,
        dl.location_id,
        UPPER(TRIM(dl.location_code)) AS region_code,
        dl.location AS region_name,
        p.total_population,
        o.total_obligations
    FROM regional_population p
    INNER JOIN regional_obligations o
        ON p.year_id = o.year_id
       AND p.location_id = o.location_id
    INNER JOIN pondolens.dev_gold.dim_location dl
        ON p.location_id = dl.location_id
    INNER JOIN pondolens.dev_gold.dim_year dy
        ON p.year_id = dy.year_id
    WHERE LOWER(TRIM(dl.geographic_level)) = 'region'
      AND p.total_population > 0
      AND o.total_obligations >= 0
),

regional_shares AS (
    SELECT
        *,
        ROUND(
            100.0 * total_population /
            NULLIF(
                SUM(total_population) OVER (PARTITION BY year),
                0
            ), 2
        ) AS population_share_pct,

        ROUND(
            100.0 * total_obligations /
            NULLIF(
                SUM(total_obligations) OVER (PARTITION BY year),
                0
            ), 2
        ) AS spending_share_pct,

        ROUND(
            total_obligations /
            NULLIF(total_population, 0),
            2
        ) AS spending_per_person_php

    FROM combined
)

SELECT
    year,
    location_id,
    region_code,
    region_name,
    total_population,
    total_obligations,

    population_share_pct,
    spending_share_pct,

    ROUND(
        spending_share_pct - population_share_pct,
        2
    ) AS share_gap_pp,

    spending_per_person_php,

    ROW_NUMBER() OVER (
        PARTITION BY year
        ORDER BY spending_share_pct DESC, region_code
    ) AS region_sort_order

FROM regional_shares;
