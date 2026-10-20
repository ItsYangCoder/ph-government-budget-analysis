"""Exercise the profiling SQL guard against persistent writes and parser fallbacks."""
import importlib.util
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location(
    'check_profiling', Path(__file__).resolve().parents[2] / 'scripts/check_profiling.py'
)
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


@pytest.mark.parametrize('sql', [
    'SELECT 1;', 'DESCRIBE TABLE pondolens.dev_bronze.hospital;',
    'CREATE OR REPLACE TEMP VIEW hospital_profile AS SELECT 1;',
    'WITH t AS (SELECT 1) SELECT * FROM t;',
])
def test_allows_read_only_profiling(sql):
    assert checks.validate_sql(sql, 'fixture') == []


@pytest.mark.parametrize('sql', [
    'DELETE FROM pondolens.dev_bronze.hospital;',
    'CREATE TABLE target AS SELECT 1;',
    'CREATE VIEW target AS SELECT 1;',
    'CREATE TEMP VIEW schema_name.target AS SELECT 1;',
    'INSERT INTO target SELECT 1;',
    'DROP VIEW target;',
    'ALTER TABLE target ADD COLUMN x INT;',
    "EXECUTE IMMEDIATE 'DELETE FROM target';",
    'SELECT 1; UPDATE target SET x=1;',
    'CREATE TEMP VIEW t AS SELECT * FROM (',
])
def test_rejects_writes_or_unparsed_sql(sql):
    assert checks.validate_sql(sql, 'fixture')


def test_rejects_session_view_collision():
    views = set()
    assert checks.validate_sql('CREATE TEMP VIEW t AS SELECT 1', 'first', views) == []
    assert checks.validate_sql('CREATE TEMP VIEW t AS SELECT 2', 'second', views)


def test_registered_packages():
    assert checks.validate() == []
