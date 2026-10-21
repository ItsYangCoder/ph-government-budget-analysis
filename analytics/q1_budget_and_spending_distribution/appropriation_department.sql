CREATE OR REPLACE VIEW pondolens.dev_gold.analytics_budget_distribution_by_department
AS
WITH dept_yearly AS (
    -- Total appropriations for each department and year.
    SELECT
        y.year,
        UPPER(TRIM(p.particular)) AS department,
        SUM(fe.appropriation_amount) AS total_appropriation_php
    FROM pondolens.dev_gold.fact_regional_expenditure fe
    INNER JOIN pondolens.dev_gold.dim_year y
        ON fe.year_id = y.year_id
    INNER JOIN pondolens.dev_gold.dim_particular p
        ON fe.particular_id = p.particular_id
    INNER JOIN pondolens.dev_gold.dim_location l
        ON fe.location_id = l.location_id
    WHERE y.year BETWEEN 2021 AND 2025
      AND UPPER(TRIM(p.category)) = 'DEPARTMENTS'
      AND UPPER(TRIM(l.geographic_level)) = 'REGION'
      AND UPPER(TRIM(p.particular)) NOT IN (
          '', 'ALL', 'TOTAL', 'GRAND TOTAL'
      )
    GROUP BY
        y.year,
        UPPER(TRIM(p.particular))
),

dept_ranked AS (
    -- Rank departments by appropriations within each year.
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY year
            ORDER BY
                total_appropriation_php DESC NULLS LAST,
                department ASC
        ) AS department_rank
    FROM dept_yearly
),

grouped AS (
    -- Keep the top three and combine the rest into Others.
    SELECT
        year,
        CASE
            WHEN department_rank <= 3 THEN department
            ELSE 'Other departments'
        END AS department_group,
        SUM(total_appropriation_php) AS total_appropriation_php
    FROM dept_ranked
    GROUP BY
        year,
        CASE
            WHEN department_rank <= 3 THEN department
            ELSE 'Other departments'
        END
),

yearly_totals AS (
    -- Total appropriations from the same filtered departments.
    SELECT
        year,
        SUM(total_appropriation_php) AS yearly_total_php
    FROM dept_yearly
    GROUP BY year
)

SELECT
    g.year,
    g.department_group,
    g.total_appropriation_php,
    t.yearly_total_php,
    ROUND(
        100.0 * g.total_appropriation_php
        / NULLIF(t.yearly_total_php, 0),
        4
    ) AS percentage_share
FROM grouped g
INNER JOIN yearly_totals t
    ON g.year = t.year;