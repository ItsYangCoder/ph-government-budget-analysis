CREATE OR REPLACE VIEW pondolens.dev_gold.budget_department AS
WITH particular_yearly AS (
    -- Department appropriations across regions, Nationwide and Central Office.
    SELECT
        y.year,
        UPPER(TRIM(p.particular)) AS particular,
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
        UPPER(TRIM(p.particular))
),

particular_ranked AS (
    -- Find the top three departments for each year.
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY year
            ORDER BY
                total_appropriation_php DESC NULLS LAST,
                particular ASC
        ) AS particular_rank
    FROM particular_yearly
),

grouped AS (
    -- Combine the remaining departments into Other Departments.
    SELECT
        year,
        CASE
            WHEN particular_rank <= 3 THEN particular
            ELSE 'OTHER DEPARTMENTS'
        END AS particular_group,
        SUM(total_appropriation_php) AS total_appropriation_php
    FROM particular_ranked
    GROUP BY
        year,
        CASE
            WHEN particular_rank <= 3 THEN particular
            ELSE 'OTHER DEPARTMENTS'
        END
),

yearly_totals AS (
    -- Calculate total department appropriations for each year.
    SELECT
        year,
        SUM(total_appropriation_php) AS yearly_total_php
    FROM particular_yearly
    GROUP BY year
)

SELECT
    g.year,
    CASE
        WHEN g.particular_group = 'OTHER DEPARTMENTS'
            THEN g.particular_group
        ELSE REGEXP_REPLACE(
            g.particular_group,
            '^(DEPARTMENT OF (THE )?|THE )',
            ''
        )
    END AS particular_group,
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