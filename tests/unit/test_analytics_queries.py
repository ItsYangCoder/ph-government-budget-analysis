"""Exercise regional joins and age-bin totals with a small SQLite fixture.

Databricks syntax is parsed/transpiled by sqlglot; this is not a warehouse test.
"""
import sqlite3
import pytest
from pathlib import Path
import sqlglot
from sqlglot import exp


@pytest.mark.parametrize("invalid_group", ["null", "missing", "duplicate", "negative"])
def test_ap2_ap3_region_year_aggregation(invalid_group):
    c=sqlite3.connect(':memory:')
    c.create_function('TRY_DIVIDE',2,lambda x,y: x/y if x is not None and y else None)
    c.executescript('''
    CREATE TABLE dim_location(location_id INT,location_code TEXT,location TEXT,geographic_level TEXT);
    INSERT INTO dim_location VALUES (1,'I','Ilocos','region'),(2,'II','Cagayan','region'),(3,'III','Missing','region'),(4,'CO','Central','office');
    CREATE TABLE dim_year(year_id INT,year INT); INSERT INTO dim_year VALUES(1,2024);
    CREATE TABLE dim_particular(particular_id INT,category TEXT); INSERT INTO dim_particular VALUES(1,'DEPARTMENTS'),(2,'UNKNOWN');
    CREATE TABLE dim_age_group(age_group_id INT,age_min INT,age_max INT); INSERT INTO dim_age_group VALUES(1,0,4),(2,5,9);
    CREATE TABLE fact_population(year_id INT,location_id INT,age_group_id INT,population_count INT);
    INSERT INTO fact_population VALUES(1,1,1,100),(1,1,2,200),(1,2,1,50),(1,2,2,50),(1,3,1,100),(1,3,2,NULL);
    CREATE TABLE fact_regional_expenditure(year_id INT,location_id INT,particular_id INT,obligation_amount INT);
    INSERT INTO fact_regional_expenditure VALUES(1,1,1,600),(1,2,1,100),(1,3,1,100),(1,4,1,9999),(1,1,2,9999);
    CREATE TABLE dim_indicator(indicator_id INT,indicator TEXT,measure_type TEXT,unit TEXT);
    INSERT INTO dim_indicator VALUES(1,'grdp_per_capita','grdp_per_capita_constant_2018_prices','PHP/person (2018 prices)'),(2,'grdp_per_capita','grdp_per_capita_current_prices','PHP/person');
    CREATE TABLE fact_regional_indicator(year_id INT,location_id INT,indicator_id INT,measurement INT);
    INSERT INTO fact_regional_indicator VALUES(1,1,1,100000),(1,2,1,90000),(1,1,2,150000),(1,3,1,80000);
    ''')
    if invalid_group == 'missing':
        c.execute('DELETE FROM fact_population WHERE location_id=3 AND age_group_id=2')
    elif invalid_group == 'duplicate':
        c.execute('UPDATE fact_population SET population_count=100 WHERE location_id=3')
        c.execute('INSERT INTO fact_population VALUES(1,3,1,100)')
    elif invalid_group == 'negative':
        c.execute('UPDATE fact_population SET population_count=-1 WHERE location_id=3 AND age_group_id=2')
    # All-age totals must not be added to the detail age bins.
    c.execute('INSERT INTO dim_age_group VALUES(99,NULL,NULL)')
    c.execute('INSERT INTO fact_population VALUES(1,1,99,300)')
    def query(path,create=False):
     tree=sqlglot.parse((Path(__file__).resolve().parents[2] / path).read_text().removeprefix('%sql'),read='databricks')[0]
     if create:tree=tree.expression
     for t in tree.find_all(exp.Table):t.set('db',None);t.set('catalog',None)
     return c.execute(tree.sql(dialect='sqlite')).fetchall()
    r=query('analytics/q2_budget_and_population/regional_obligations_per_capita_benchmark.sql')
    assert len(r)==2,r
    assert sorted((x[0],x[3],x[4]) for x in r)==[('I',300,2.0),('II',100,1.0)],r
    r=query('analytics/q3_budget_and_indicators/budget_vs_grdp.sql',True)
    assert len(r)==2,r
    assert sorted((x[2],x[4],x[5],x[6],x[7]) for x in r)==[('I',100000,2,300,600),('II',90000,1,100,100)],r
    r=query('analytics/q2_budget_and_population/population_budget_share_gap.sql',True)
    assert sorted((x[2],x[4]) for x in r)==[('I',300),('II',100)],r
