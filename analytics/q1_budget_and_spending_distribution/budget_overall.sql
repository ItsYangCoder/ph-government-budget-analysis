CREATE OR REPLACE VIEW pondolens.dev_gold.budget_overall AS
SELECT
    f.regional_expenditure_id,
    y.year,
    l.location,
    REGEXP_REPLACE(
        UPPER(TRIM(p.particular)),
        '^(DEPARTMENT OF (THE )?|THE )',
        ''
    ) AS particular,
    f.appropriation_amount,
    f.appropriation_value_status,
    f.obligation_amount,
    f.obligation_value_status,
    f.processed_at
FROM pondolens.dev_gold.fact_regional_expenditure f
JOIN pondolens.dev_gold.dim_year y
    ON f.year_id = y.year_id
JOIN pondolens.dev_gold.dim_location l
    ON f.location_id = l.location_id
JOIN pondolens.dev_gold.dim_particular p
    ON f.particular_id = p.particular_id
WHERE REGEXP_REPLACE(
          UPPER(TRIM(p.particular)),
          '[.]+$',
          ''
      ) NOT IN (
          'ALL', 'TOTAL', 'GRAND TOTAL'
      );