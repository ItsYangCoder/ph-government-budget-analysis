{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

CREATE TABLE IF NOT EXISTS {{ this }} (
  source_region STRING,
  region_code STRING,
  region_name STRING,
  valid_from_year INT,
  valid_to_year INT,
  source_code STRING,
  geographic_level STRING
)
-- pondolens:statement --
CREATE OR REPLACE TEMP VIEW crosswalk_expected AS
WITH canonical_regions AS (
  SELECT *
  FROM VALUES
    ('I',     'Ilocos Region', 'region'),
    ('II',    'Cagayan Valley', 'region'),
    ('III',   'Central Luzon', 'region'),
    ('IVA',   'CALABARZON', 'region'),
    ('IVB',   'MIMAROPA', 'region'),
    ('V',     'Bicol Region', 'region'),
    ('VI',    'Western Visayas', 'region'),
    ('VII',   'Central Visayas', 'region'),
    ('VIII',  'Eastern Visayas', 'region'),
    ('IX',    'Zamboanga Peninsula', 'region'),
    ('X',     'Northern Mindanao', 'region'),
    ('XI',    'Davao Region', 'region'),
    ('XII',   'SOCCSKSARGEN', 'region'),
    ('XIII',  'Caraga', 'region'),
    ('NCR',   'National Capital Region', 'region'),
    ('CAR',   'Cordillera Administrative Region', 'region'),
    ('BARMM', 'Bangsamoro Autonomous Region in Muslim Mindanao', 'region'),
    ('NIR',   'Negros Island Region', 'region'),
    ('CO',    'Central Office', 'other'),
    ('PHL',   'Philippines', 'nationwide')
  AS c(region_code, region_name, geographic_level)
),
source_aliases AS (
  SELECT *
  FROM VALUES
    ('National',
     'PHL', NULL, 2021, 2025),

    ('CENTRAL OFFICE',
     'CO', NULL, 2021, 2025),

    ('BANGSAMORO AUTONOMOUS REGION IN MUSLIM MINDANAO (BARMM)',
     'BARMM', 'BARMM', 2022, 2025),

    ('BANGSAMORO AUTONOMOUS REGION IN MUSLIM MINDANAO (BARMM/ARMM)',
     'BARMM', 'BARMM/ARMM', 2021, 2021),

    ('BARMM',
     'BARMM', 'BARMM', 2021, 2025),

    ('CAR',
     'CAR', 'CAR', 2021, 2025),

    ('CORDILLERA ADMINISTRATIVE REGION (CAR)',
     'CAR', 'CAR', 2021, 2025),

    ('REGION I (ILOCOS REGION)',
     'I', 'I', 2021, 2025),

    ('Region I (Ilocos Region)',
     'I', 'I', 2021, 2025),

    ('REGION II (CAGAYAN VALLEY)',
     'II', 'II', 2021, 2025),

    ('Region II (Cagayan Valley)',
     'II', 'II', 2021, 2025),

    ('REGION III (CENTRAL LUZON)',
     'III', 'III', 2021, 2025),

    ('Region III (Central Luzon)',
     'III', 'III', 2021, 2025),

    ('REGION IV-A (CALABARZON)',
     'IVA', 'IV-A', 2024, 2025),

    ('REGION IVA (CALABARZON)',
     'IVA', 'IVA', 2022, 2024),

    ('REGION IVA CALABARZON',
     'IVA', 'IVA', 2021, 2021),

    ('Region IV-A (CALABARZON)',
     'IVA', 'IV-A', 2021, 2025),

    ('MIMAROPA',
     'IVB', NULL, 2021, 2025),

    ('MIMAROPA REGION',
     'IVB', NULL, 2021, 2025),

    ('REGION IX (ZAMBOANGA PENINSULA)',
     'IX', 'IX', 2021, 2025),

    ('Region IX (Zamboanga Peninsula)',
     'IX', 'IX', 2021, 2025),

    ('NATIONAL CAPITAL REGION (NCR)',
     'NCR', 'NCR', 2021, 2025),

    ('NCR',
     'NCR', 'NCR', 2021, 2025),

    ('NEGROS ISLAND REGION (NIR)',
     'NIR', 'NIR', 2024, 2025),

    ('REGION V (BICOL REGION)',
     'V', 'V', 2021, 2025),

    ('Region V (Bicol Region)',
     'V', 'V', 2021, 2025),

    ('REGION VI (WESTERN VISAYAS)',
     'VI', 'VI', 2021, 2025),

    ('Region VI (Western Visayas)',
     'VI', 'VI', 2021, 2025),

    ('REGION VII (CENTRAL VISAYAS)',
     'VII', 'VII', 2021, 2025),

    ('Region VII (Central Visayas)',
     'VII', 'VII', 2021, 2025),

    ('REGION VIII (EASTERN VISAYAS)',
     'VIII', 'VIII', 2021, 2025),

    ('Region VIII (Eastern Visayas)',
     'VIII', 'VIII', 2021, 2025),

    ('REGION X (NORTHERN MINDANAO)',
     'X', 'X', 2021, 2025),

    ('Region X (Northern Mindanao)',
     'X', 'X', 2021, 2025),

    ('REGION XI (DAVAO REGION)',
     'XI', 'XI', 2021, 2025),

    ('Region XI (Davao Region)',
     'XI', 'XI', 2021, 2025),

    ('REGION XII (SOCCSKSARGEN)',
     'XII', 'XII', 2021, 2025),

    ('Region XII (SOCCSKSARGEN)',
     'XII', 'XII', 2021, 2025),

    ('REGION XIII (CARAGA)',
     'XIII', 'XIII', 2021, 2025),

    ('Region XIII (Caraga)',
     'XIII', 'XIII', 2021, 2025)

  AS a(
    source_region,
    region_code,
    source_code,
    valid_from_year,
    valid_to_year
  )
)
SELECT
  a.source_region,
  a.region_code,
  c.region_name,
  a.valid_from_year,
  a.valid_to_year,
  CAST(a.source_code AS STRING) AS source_code,
  c.geographic_level
FROM source_aliases a
JOIN canonical_regions c
  ON a.region_code = c.region_code
-- pondolens:statement --
-- 4. Update existing aliases or insert missing aliases.
MERGE INTO {{ this }} AS t
USING crosswalk_expected AS s
ON t.source_region = s.source_region

WHEN MATCHED THEN UPDATE SET
  t.region_code = s.region_code,
  t.region_name = s.region_name,
  t.valid_from_year = LEAST(t.valid_from_year, s.valid_from_year),
  t.valid_to_year = GREATEST(t.valid_to_year, s.valid_to_year),
  t.source_code = s.source_code,
  t.geographic_level = s.geographic_level

WHEN NOT MATCHED THEN INSERT (
  source_region,
  region_code,
  region_name,
  valid_from_year,
  valid_to_year,
  source_code,
  geographic_level
)
VALUES (
  s.source_region,
  s.region_code,
  s.region_name,
  s.valid_from_year,
  s.valid_to_year,
  s.source_code,
  s.geographic_level
)
-- pondolens:statement --
-- 5. Validate mappings.
-- Expected: no rows.
SELECT
  s.source_region,
  s.region_code AS expected_region_code,
  t.region_code AS actual_region_code,
  s.region_name AS expected_region_name,
  t.region_name AS actual_region_name
FROM crosswalk_expected s
LEFT JOIN {{ this }} t
  ON t.source_region = s.source_region
WHERE t.source_region IS NULL
   OR NOT (t.region_code <=> s.region_code)
   OR NOT (t.region_name <=> s.region_name)
   OR NOT (t.source_code <=> s.source_code)
   OR NOT (t.geographic_level <=> s.geographic_level)
   OR t.valid_from_year IS NULL
   OR t.valid_to_year IS NULL
   OR t.valid_from_year > s.valid_from_year
   OR t.valid_to_year < s.valid_to_year
-- pondolens:statement --
-- 6. Check overlapping duplicate exact aliases.
-- Expected: no rows.
WITH alias_years AS (
  SELECT
    source_region,
    EXPLODE(
      SEQUENCE(valid_from_year, valid_to_year)
    ) AS year
  FROM {{ this }}
  WHERE valid_from_year <= valid_to_year
)
SELECT
  source_region,
  year,
  COUNT(*) AS matching_rows
FROM alias_years
GROUP BY source_region, year
HAVING COUNT(*) > 1
-- pondolens:statement --
-- 7. Final preview: seven columns, without country.
SELECT
  source_region,
  region_code,
  region_name,
  valid_from_year,
  valid_to_year,
  source_code,
  geographic_level
FROM {{ this }}
ORDER BY geographic_level, region_code, source_region
