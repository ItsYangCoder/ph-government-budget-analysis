{{ config(materialized='pondolens_script', database=var('pondolens_catalog')) }}

-- Object: persistent Delta table
-- Grain: category × canonical agency/fund
-- IDs: fixed; preserve existing assignments
--
-- OFFICE OF THE PRESS SECRETARY is an alias of:
--   30033 = PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)
--
-- 30051 is retired and must never be reused.
-- Any existing 30051 row is retained temporarily until all
-- dependent fact references have been migrated.
-- ============================================================


-- ============================================================
-- 1. APPROVED CANONICAL REGISTRY
-- 51 entries including UNKNOWN.
-- ============================================================

CREATE OR REPLACE TEMP VIEW dim_particular_seed AS
SELECT *
FROM VALUES
    (30000, 'UNKNOWN', 'UNKNOWN'),
    (30001, 'DEPARTMENTS', 'CIVIL SERVICE COMMISSION (CSC)'),
    (30002, 'DEPARTMENTS', 'COMMISSION ON AUDIT (COA)'),
    (30003, 'DEPARTMENTS', 'COMMISSION ON ELECTIONS (COMELEC)'),
    (30004, 'DEPARTMENTS', 'COMMISSION ON HUMAN RIGHTS (CHR)'),
    (30005, 'DEPARTMENTS', 'CONGRESS OF THE PHILIPPINES (CONGRESS)'),
    (30006, 'DEPARTMENTS', 'DEPARTMENT OF AGRARIAN REFORM (DAR)'),
    (30007, 'DEPARTMENTS', 'DEPARTMENT OF AGRICULTURE (DA)'),
    (30008, 'DEPARTMENTS', 'DEPARTMENT OF BUDGET AND MANAGEMENT (DBM)'),
    (30009, 'DEPARTMENTS', 'DEPARTMENT OF EDUCATION (DEPED)'),
    (30010, 'DEPARTMENTS', 'DEPARTMENT OF ENERGY (DOE)'),
    (30011, 'DEPARTMENTS', 'DEPARTMENT OF ENVIRONMENT AND NATURAL RESOURCES (DENR)'),
    (30012, 'DEPARTMENTS', 'DEPARTMENT OF FINANCE (DOF)'),
    (30013, 'DEPARTMENTS', 'DEPARTMENT OF FOREIGN AFFAIRS (DFA)'),
    (30014, 'DEPARTMENTS', 'DEPARTMENT OF HEALTH (DOH)'),
    (30015, 'DEPARTMENTS', 'DEPARTMENT OF HUMAN SETTLEMENTS AND URBAN DEVELOPMENT (DHSUD)'),
    (30016, 'DEPARTMENTS', 'DEPARTMENT OF INFORMATION AND COMMUNICATIONS TECHNOLOGY (DICT)'),
    (30017, 'DEPARTMENTS', 'DEPARTMENT OF JUSTICE (DOJ)'),
    (30018, 'DEPARTMENTS', 'DEPARTMENT OF LABOR AND EMPLOYMENT (DOLE)'),
    (30019, 'DEPARTMENTS', 'DEPARTMENT OF NATIONAL DEFENSE (DND)'),
    (30020, 'DEPARTMENTS', 'DEPARTMENT OF PUBLIC WORKS AND HIGHWAYS (DPWH)'),
    (30021, 'DEPARTMENTS', 'DEPARTMENT OF SCIENCE AND TECHNOLOGY (DOST)'),
    (30022, 'DEPARTMENTS', 'DEPARTMENT OF SOCIAL WELFARE AND DEVELOPMENT (DSWD)'),
    (30023, 'DEPARTMENTS', 'DEPARTMENT OF THE INTERIOR AND LOCAL GOVERNMENT (DILG)'),
    (30024, 'DEPARTMENTS', 'DEPARTMENT OF TOURISM (DOT)'),
    (30025, 'DEPARTMENTS', 'DEPARTMENT OF TRADE AND INDUSTRY (DTI)'),
    (30026, 'DEPARTMENTS', 'DEPARTMENT OF TRANSPORTATION (DOTR)'),
    (30027, 'DEPARTMENTS', 'JOINT LEGISLATIVE-EXECUTIVE COUNCILS'),
    (30028, 'DEPARTMENTS', 'NATIONAL ECONOMIC AND DEVELOPMENT AUTHORITY (NEDA)'),
    (30029, 'DEPARTMENTS', 'OFFICE OF THE OMBUDSMAN (OMB)'),
    (30030, 'DEPARTMENTS', 'OFFICE OF THE PRESIDENT (OP)'),
    (30031, 'DEPARTMENTS', 'OFFICE OF THE VICE-PRESIDENT (OVP)'),
    (30032, 'DEPARTMENTS', 'OTHER EXECUTIVE OFFICES (OEOS)'),
    (30033, 'DEPARTMENTS', 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'),
    (30034, 'DEPARTMENTS', 'STATE UNIVERSITIES AND COLLEGES (SUCS)'),
    (30035, 'DEPARTMENTS', 'THE JUDICIARY (JUD)'),
    (30036, 'SPECIAL PURPOSE FUNDS', 'ALLOCATIONS TO LOCAL GOVERNMENT UNITS (ALGU)'),
    (30037, 'SPECIAL PURPOSE FUNDS', 'BUDGETARY SUPPORT TO GOVERNMENT CORPORATIONS (BSGC)'),
    (30038, 'SPECIAL PURPOSE FUNDS', 'CONTINGENT FUND'),
    (30039, 'SPECIAL PURPOSE FUNDS', 'CUSTOMS DUTIES AND TAXES, INCLUDING TAX EXPENDITURES'),
    (30040, 'SPECIAL PURPOSE FUNDS', 'DEBT INTEREST PAYMENTS'),
    (30041, 'SPECIAL PURPOSE FUNDS', 'MISCELLANEOUS PERSONNEL BENEFITS FUND'),
    (30042, 'SPECIAL PURPOSE FUNDS', 'NATIONAL DISASTER RISK REDUCTION AND MANAGEMENT FUND (CALAMITY FUND)'),
    (30043, 'SPECIAL PURPOSE FUNDS', 'NET LENDING'),
    (30044, 'SPECIAL PURPOSE FUNDS', 'PENSION AND GRATUITY FUND'),
    (30045, 'DEPARTMENTS', 'DEPARTMENT OF MIGRANT WORKERS (DMW)'),
    (30046, 'SPECIAL PURPOSE FUNDS', 'REVISED AFP MODERNIZATION PROGRAM'),
    (30047, 'AUTOMATIC APPROPRIATIONS', 'BARMM - ANNUAL BLOCK GRANT'),
    (30048, 'AUTOMATIC APPROPRIATIONS', 'DEBT INTEREST PAYMENTS'),
    (30049, 'AUTOMATIC APPROPRIATIONS', 'NATIONAL TAX ALLOTMENT'),
    (30050, 'AUTOMATIC APPROPRIATIONS', 'NET LENDING')
AS r(particular_id, category, particular)
-- pondolens:statement --
-- ============================================================
-- 2. VALIDATE REGISTRY
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 51
    AND COUNT(DISTINCT particular_id) = 51
    AND COUNT_IF(
        particular_id IS NULL
        OR particular_id NOT BETWEEN 30000 AND 30050
        OR category IS NULL OR TRIM(category) = ''
        OR particular IS NULL OR TRIM(particular) = ''
    ) = 0
    AND COUNT_IF(
        particular_id = 30033
        AND category = 'DEPARTMENTS'
        AND particular = 'PRESIDENTIAL COMMUNICATIONS OFFICE (PCO)'
    ) = 1,
    'STOP: Invalid canonical registry or PCO definition.'
)
FROM dim_particular_seed
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate registry business keys.'
)
FROM (
    SELECT category, particular
    FROM dim_particular_seed
    GROUP BY category, particular
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- ============================================================
-- 3. CREATE PERSISTENT DELTA TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS {{ this }} (
    particular_id INT NOT NULL
        COMMENT 'Stable identifier; 30000 UNKNOWN; 30051 retired',
    category STRING NOT NULL
        COMMENT 'Standard agency or fund category',
    particular STRING NOT NULL
        COMMENT 'Canonical agency or fund name, uppercase',
    processed_at TIMESTAMP NOT NULL
)
USING DELTA
COMMENT 'Fixed canonical particular registry for expenditure facts.'
-- pondolens:statement --
-- ============================================================
-- 4. VALIDATE EXISTING TARGET
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT particular_id)
    AND COUNT_IF(
        particular_id IS NULL
        OR particular_id NOT BETWEEN 30000 AND 39999
        OR category IS NULL OR TRIM(category) = ''
        OR particular IS NULL OR TRIM(particular) = ''
    ) = 0,
    'STOP: Invalid existing dimension IDs or attributes.'
)
FROM {{ this }}
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate existing dimension business keys.'
)
FROM (
    SELECT category, particular
    FROM {{ this }}
    GROUP BY category, particular
    HAVING COUNT(*) > 1
) duplicates
-- pondolens:statement --
-- Preserve existing ID-to-definition assignments.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing ID conflicts with the approved registry.'
)
FROM {{ this }} t
JOIN dim_particular_seed s
    ON t.particular_id = s.particular_id
WHERE NOT (t.category <=> s.category)
   OR NOT (t.particular <=> s.particular)
-- pondolens:statement --
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing definition has a different ID.'
)
FROM {{ this }} t
JOIN dim_particular_seed s
    ON t.category = s.category
   AND t.particular = s.particular
WHERE t.particular_id <> s.particular_id
-- pondolens:statement --
-- Any retained 30051 entry must remain the original legacy definition.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Retired ID 30051 has an unexpected definition.'
)
FROM {{ this }}
WHERE particular_id = 30051
  AND (
      NOT (category <=> 'DEPARTMENTS')
      OR NOT (particular <=> 'OFFICE OF THE PRESS SECRETARY')
  )
-- pondolens:statement --
-- ============================================================
-- 5. INSERT MISSING CANONICAL DEFINITIONS
-- No deletion while legacy facts may still reference 30051.
-- ============================================================

MERGE INTO {{ this }} t
USING dim_particular_seed s
ON t.particular_id = s.particular_id

WHEN NOT MATCHED THEN INSERT (
    particular_id,
    category,
    particular,
    processed_at
)
VALUES (
    s.particular_id,
    s.category,
    s.particular,
    CURRENT_TIMESTAMP()
)
-- pondolens:statement --
-- ============================================================
-- 6. VERIFY ALL ACTIVE DEFINITIONS
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 51
    AND COUNT_IF(
        t.particular_id IS NULL
        OR NOT (t.category <=> s.category)
        OR NOT (t.particular <=> s.particular)
    ) = 0,
    'STOP: Saved canonical definitions do not match the registry.'
)
FROM dim_particular_seed s
LEFT JOIN {{ this }} t
    ON s.particular_id = t.particular_id
-- pondolens:statement --
-- ============================================================
-- 7. FINAL RESULTS
-- Active registry excludes retired 30051.
-- ============================================================

SELECT
    COUNT(*) AS active_registry_rows,
    COUNT(DISTINCT t.particular_id) AS active_unique_ids
FROM {{ this }} t
JOIN dim_particular_seed s
    ON t.particular_id = s.particular_id
-- pondolens:statement --
SELECT *
FROM {{ this }}
WHERE particular_id = 30033
-- pondolens:statement --
SELECT
    COUNT(*) AS retained_legacy_rows
FROM {{ this }}
WHERE particular_id = 30051
-- pondolens:statement --
SELECT ASSERT_TRUE(COUNT_IF(processed_at IS NULL) = 0, 'Missing dim_particular processed_at') FROM {{ this }}
