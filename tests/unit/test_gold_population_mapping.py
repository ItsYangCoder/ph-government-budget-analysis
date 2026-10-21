"""Execute the model's mapping guard on small fixtures before any target write.

SQLite executes SQL transpiled from Databricks; this is an offline check.
"""
import sqlite3
import re
from pathlib import Path

import pytest
import sqlglot


@pytest.mark.parametrize('problem', [None, 'year', 'location', 'age', 'duplicate', 'null', 'negative'])
def test_population_mapping_guard(problem):
    c = sqlite3.connect(':memory:')

    def assert_true(value, message):
        if not value:
            raise ValueError(message)

    c.create_function('ASSERT_TRUE', 2, assert_true)
    c.executescript('''
        CREATE TABLE population(year INT, region_code TEXT, age_group TEXT, sex TEXT, population INT);
        INSERT INTO population VALUES(2024,'I','0 - 4','Both',100),(2024,'I','5 - 9','Both',200);
        CREATE TABLE dim_year(year_id INT, year INT);
        INSERT INTO dim_year VALUES(20000,2024);
        CREATE TABLE dim_location(location_id BIGINT, location_code TEXT);
        INSERT INTO dim_location VALUES(3000000000,'I');
        CREATE TABLE dim_age_group(age_group_id INT, age_group TEXT);
        INSERT INTO dim_age_group VALUES(1,'0 - 4'),(2,'5 - 9');
    ''')
    changes = {
        'year': 'DELETE FROM dim_year',
        'location': 'DELETE FROM dim_location',
        'age': 'DELETE FROM dim_age_group WHERE age_group_id=2',
        'duplicate': "INSERT INTO dim_location VALUES(3000000001,'I')",
        'null': "UPDATE population SET population=NULL WHERE age_group='5 - 9'",
        'negative': "UPDATE population SET population=-1 WHERE age_group='5 - 9'",
    }
    if problem:
        c.execute(changes[problem])
    source = (Path(__file__).resolve().parents[2] / 'dbt/models/gold/fact_population.sql').read_text()
    rendered = re.sub(r"\{\{ config\(.*?\) \}\}", '', source)
    rendered = re.sub(r"\{\{ ref\('([^']+)'\) \}\}", r'\1', rendered)
    rendered = rendered.replace('{{ this }}', 'gold_target')
    statements = rendered.split('-- pondolens:statement --')
    stage = sqlglot.parse_one(statements[0], read='databricks')
    stage.set('replace', False)  # SQLite supports CREATE VIEW, not CREATE OR REPLACE.
    c.execute(stage.sql(dialect='sqlite'))
    guard = sqlglot.parse_one(statements[1], read='databricks').sql(dialect='sqlite')
    if problem:
        with pytest.raises(sqlite3.OperationalError, match='user-defined function'):
            c.execute(guard).fetchall()
        assert c.execute("SELECT COUNT(*) FROM sqlite_master WHERE name='gold_target'").fetchone()[0] == 0
    else:
        c.execute(guard).fetchall()
        assert c.execute('SELECT COUNT(*), SUM(population_count), MAX(location_id) FROM dbt_population_with_keys').fetchone() == (2, 300, 3000000000)
