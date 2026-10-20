-- ============================================================
-- PondoLens | Gold: dim_particular
-- Author: Christine Joy D. Balansay
--
-- Object: persistent Delta table
-- Grain: one category × standardized particular
-- IDs: fixed registry; never renumber existing definitions
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
    (30050, 'AUTOMATIC APPROPRIATIONS', 'NET LENDING'),
    (30051, 'DEPARTMENTS', 'OFFICE OF THE PRESS SECRETARY')
AS r(particular_id, category, particular);


-- ============================================================
-- VALIDATE SEED
-- Update expected count when adding approved registry entries.
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 52
    AND COUNT(DISTINCT particular_id) = 52
    AND COUNT_IF(
        particular_id IS NULL
        OR particular_id NOT BETWEEN 30000 AND 39999
        OR category IS NULL OR TRIM(category) = ''
        OR particular IS NULL OR TRIM(particular) = ''
    ) = 0,
    'STOP: Invalid seed count, IDs, or required fields.'
)
FROM dim_particular_seed;


SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate seed business keys.'
)
FROM (
    SELECT category, particular
    FROM dim_particular_seed
    GROUP BY category, particular
    HAVING COUNT(*) > 1
) duplicates;


-- ============================================================
-- CREATE PERSISTENT TABLE
-- Keeps the existing three-column contract.
-- ============================================================

CREATE TABLE IF NOT EXISTS pondolens.dev_gold.dim_particular (
    particular_id INT NOT NULL
        COMMENT 'Stable fixed identifier; 30000 represents UNKNOWN',
    category STRING NOT NULL
        COMMENT 'Standard agency or fund category',
    particular STRING NOT NULL
        COMMENT 'Standard agency or fund name, uppercase'
)
USING DELTA
COMMENT 'Fixed particular registry used by fact_regional_expenditure.';


-- ============================================================
-- VALIDATE EXISTING TARGET
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = COUNT(DISTINCT particular_id)
    AND COUNT_IF(
        particular_id IS NULL
        OR particular_id NOT BETWEEN 30000 AND 39999
        OR category IS NULL OR TRIM(category) = ''
        OR particular IS NULL OR TRIM(particular) = ''
    ) = 0,
    'STOP: Invalid or duplicate existing dimension IDs.'
)
FROM pondolens.dev_gold.dim_particular;


SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Duplicate existing dimension business keys.'
)
FROM (
    SELECT category, particular
    FROM pondolens.dev_gold.dim_particular
    GROUP BY category, particular
    HAVING COUNT(*) > 1
) duplicates;


-- An existing ID cannot acquire a different definition.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing ID conflicts with the approved definition.'
)
FROM pondolens.dev_gold.dim_particular t
JOIN dim_particular_seed s
    ON t.particular_id = s.particular_id
WHERE NOT (t.category <=> s.category)
   OR NOT (t.particular <=> s.particular);


-- An existing definition cannot receive a different ID.
SELECT ASSERT_TRUE(
    COUNT(*) = 0,
    'STOP: Existing definition has a different ID.'
)
FROM pondolens.dev_gold.dim_particular t
JOIN dim_particular_seed s
    ON t.category = s.category
   AND t.particular = s.particular
WHERE t.particular_id <> s.particular_id;


-- ============================================================
-- INSERT MISSING DEFINITIONS
-- Existing definitions are preserved; no automatic deletion.
-- ============================================================

MERGE INTO pondolens.dev_gold.dim_particular t
USING dim_particular_seed s
ON t.particular_id = s.particular_id

WHEN NOT MATCHED THEN INSERT (
    particular_id,
    category,
    particular
)
VALUES (
    s.particular_id,
    s.category,
    s.particular
);


-- ============================================================
-- POST-LOAD VALIDATION
-- ============================================================

SELECT ASSERT_TRUE(
    COUNT(*) = 52
    AND COUNT_IF(
        t.particular_id IS NULL
        OR NOT (t.category <=> s.category)
        OR NOT (t.particular <=> s.particular)
    ) = 0,
    'STOP: Saved dimension does not match the approved registry.'
)
FROM dim_particular_seed s
LEFT JOIN pondolens.dev_gold.dim_particular t
    ON s.particular_id = t.particular_id;


SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT particular_id) AS unique_ids
FROM pondolens.dev_gold.dim_particular;


SELECT *
FROM pondolens.dev_gold.dim_particular
WHERE particular_id IN (30033, 30051)
ORDER BY particular_id;