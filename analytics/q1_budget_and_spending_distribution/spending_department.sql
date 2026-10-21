CREATE OR REPLACE VIEW pondolens.dev_gold.analytics_spending_distribution_by_department
AS
WITH dept_yearly AS (
    -- Total obligations for each department and year.
    SELECT
        y.year,
        UPPER(TRIM(p.particular)) AS department,
        SUM(fe.obligation_amount) AS total_obligation_php
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
    -- Find the top three independently for each year.
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY year
            ORDER BY
                total_obligation_php DESC NULLS LAST,
                department ASC
        ) AS department_rank
    FROM dept_yearly
),

grouped AS (
    -- Combine the remaining departments into Others.
    SELECT
        year,
        CASE
            WHEN department_rank <= 3 THEN department
            ELSE 'Other departments'
        END AS department_group,
        SUM(total_obligation_php) AS total_obligation_php
    FROM dept_ranked
    GROUP BY
        year,
        CASE
            WHEN department_rank <= 3 THEN department
            ELSE 'Other departments'
        END
),

yearly_totals AS (
    -- Use the same department records for the denominator.
    SELECT
        year,
        SUM(total_obligation_php) AS yearly_total_php
    FROM dept_yearly
    GROUP BY year
)

SELECT
    g.year,
    g.department_group,
    g.total_obligation_php,
    t.yearly_total_php,
    ROUND(
        100.0 * g.total_obligation_php
        / NULLIF(t.yearly_total_php, 0),
        4
    ) AS percentage_share
FROM grouped g
INNER JOIN yearly_totals t
    ON g.year = t.year;