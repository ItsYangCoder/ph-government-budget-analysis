
CREATE OR REPLACE VIEW
pondolens.dev_gold.vw_ap2_regional_alignment
AS

WITH regions AS (
    SELECT
        location_id,
        UPPER(TRIM(location_code)) AS region_code,
        location AS region_name
    FROM pondolens.dev_gold.dim_location
    WHERE LOWER(TRIM(geographic_level)) = 'region'
),

regional_population AS (
    SELECT
        fp.year_id,
        fp.location_id,
        SUM(fp.population_count) AS total_population
    FROM pondolens.dev_gold.fact_population fp
    INNER JOIN regions r
        ON fp.location_id = r.location_id
    INNER JOIN pondolens.dev_gold.dim_age_group a
        ON fp.age_group_id = a.age_group_id
    WHERE a.age_min IS NOT NULL
    GROUP BY
        fp.year_id,
        fp.location_id
    HAVING
        COUNT(*) = (
            SELECT COUNT(*)
            FROM pondolens.dev_gold.dim_age_group
            WHERE age_min IS NOT NULL
        )
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
    INNER JOIN regions r
        ON fe.location_id = r.location_id
    INNER JOIN pondolens.dev_gold.dim_particular dp
        ON fe.particular_id = dp.particular_id
    WHERE fe.obligation_amount IS NOT NULL
      AND dp.category <> 'UNKNOWN'
    GROUP BY
        fe.year_id,
        fe.location_id
),

combined AS (
    SELECT
        dy.year,
        r.location_id,
        r.region_code,
        r.region_name,
        p.total_population,
        o.total_obligations
    FROM regional_population p
    INNER JOIN regional_obligations o
        ON p.year_id = o.year_id
       AND p.location_id = o.location_id
    INNER JOIN regions r
        ON p.location_id = r.location_id
    INNER JOIN pondolens.dev_gold.dim_year dy
        ON p.year_id = dy.year_id
    WHERE p.total_population > 0
      AND o.total_obligations >= 0
),

calculated AS (
    SELECT
        *,

        SUM(total_population) OVER (
            PARTITION BY year
        ) AS national_population,

        SUM(total_obligations) OVER (
            PARTITION BY year
        ) AS national_obligations

    FROM combined
),

metrics AS (
    SELECT
        *,

        -- Regional obligations per resident
        TRY_DIVIDE(
            total_obligations,
            total_population
        ) AS per_resident_raw,

        -- Population-weighted national average
        TRY_DIVIDE(
            national_obligations,
            national_population
        ) AS national_per_resident_raw,

        -- Regional population share
        100.0 * TRY_DIVIDE(
            total_population,
            national_population
        ) AS population_share_raw,

        -- Regional obligations share
        100.0 * TRY_DIVIDE(
            total_obligations,
            national_obligations
        ) AS spending_share_raw,

        -- Expected obligations if distributed
        -- proportionally to population
        national_obligations * TRY_DIVIDE(
            total_population,
            national_population
        ) AS expected_obligations_raw

    FROM calculated
),

alignment AS (
    SELECT
        *,

        -- Percentage-point difference
        spending_share_raw - population_share_raw
            AS share_gap_raw,

        -- Actual minus population-proportional
        -- expected obligations
        total_obligations - expected_obligations_raw
            AS obligation_gap_raw,

        -- Median regional obligations per resident
        PERCENTILE_APPROX(
            per_resident_raw,
            0.5,
            10000
        ) OVER (
            PARTITION BY year
        ) AS median_per_resident_raw

    FROM metrics
)

SELECT
    year,
    location_id,
    region_code,
    region_name,

    -- Base measures
    total_population,
    total_obligations,

    -- Obligations per resident
    ROUND(per_resident_raw, 2)
        AS per_resident,

    -- National population-weighted average
    ROUND(national_per_resident_raw, 2)
        AS national_per_resident,

    -- Median across regions
    ROUND(median_per_resident_raw, 2)
        AS median_per_resident,

    -- Regional shares
    ROUND(population_share_raw, 2)
        AS population_share_pct,

    ROUND(spending_share_raw, 2)
        AS spending_share_pct,

    -- Share gap in percentage points
    ROUND(share_gap_raw, 2)
        AS share_gap_pp,

    ROUND(ABS(share_gap_raw), 2)
        AS abs_share_gap_pp,

    -- NEW: Population-proportional benchmark (PHP)
    ROUND(expected_obligations_raw, 2)
        AS expected_obligations_php,

    -- NEW: Actual minus expected obligations (PHP)
    ROUND(obligation_gap_raw, 2)
        AS obligation_gap_php,

    -- NEW: Absolute peso gap for ranking
    ROUND(ABS(obligation_gap_raw), 2)
        AS abs_obligation_gap_php,

    -- Difference from national per-resident average
    ROUND(
        per_resident_raw - national_per_resident_raw,
        2
    ) AS per_resident_difference_php,

    -- Regional per-resident value as % of national
    ROUND(
        100.0 * TRY_DIVIDE(
            per_resident_raw,
            national_per_resident_raw
        ),
        2
    ) AS per_100_national,

    -- National benchmark classification
    CASE
        WHEN per_resident_raw >= national_per_resident_raw
            THEN 'Above national average'
        ELSE 'Below national average'
    END AS vs_national,

    -- Share gap classification
    CASE
        WHEN share_gap_raw < -1
            THEN 'Below population share'
        WHEN share_gap_raw > 1
            THEN 'Above population share'
        ELSE 'Near population share'
    END AS share_gap_status,

    -- Peso gap direction
    CASE
        WHEN obligation_gap_raw > 0
            THEN 'Above proportional benchmark'
        WHEN obligation_gap_raw < 0
            THEN 'Below proportional benchmark'
        ELSE 'Equal to proportional benchmark'
    END AS obligation_gap_status

FROM alignment;
