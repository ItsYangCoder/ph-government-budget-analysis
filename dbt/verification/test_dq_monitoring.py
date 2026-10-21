"""Offline hook and run-status checks; Databricks execution is tested separately."""
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

import pytest
import sqlglot
from sqlglot import exp
from jinja2 import Environment


class Returned(Exception):
    def __init__(self, value):
        self.value = value


def render_hook(command='build', statuses=('success', 'pass'), gold='prod_gold', selected=None, fail_write=False):
    calls = []
    nodes = {
        'model.pondolens.population': SimpleNamespace(unique_id='model.pondolens.population', name='population', resource_type='model', database='pondolens', schema='prod_silver', alias='population'),
        'test.pondolens.population': SimpleNamespace(unique_id='test.pondolens.population', name="population's check", resource_type='test', depends_on=SimpleNamespace(nodes=['model.pondolens.population'])),
    }
    results = [SimpleNamespace(node=n, status=s, failures=1 if s=='fail' else None, execution_time=0.1) for n,s in zip(nodes.values(), statuses)]
    def return_value(value):
        raise Returned(value)
    def run_query(sql):
        if fail_write and 'MERGE INTO' in sql:
            raise RuntimeError('write failed')
        calls.append(sql)
    env=Environment(extensions=['jinja2.ext.do'])
    import json
    ctx=dict(execute=True, flags=SimpleNamespace(WHICH=command), results=results,
             var=lambda n,d=None: {'pondolens_catalog':'pondolens','gold_schema':gold}.get(n,d),
             adapter=SimpleNamespace(quote=lambda s:'`'+s.replace('`','``')+'`'),
             graph=SimpleNamespace(nodes=nodes,sources={}), selected_resources=selected or list(nodes),
             invocation_id='run-1', dbt_version='1.10.15', run_started_at=datetime(2026,10,22,tzinfo=timezone.utc),
             tojson=json.dumps, run_query=run_query, log=lambda *a,**k:'', **{'return':return_value})
    module=env.from_string((Path(__file__).resolve().parents[1]/'macros/dq_monitoring.sql').read_text()).make_module(ctx)
    try:
        module.record_dq_results(results)
    except Returned:
        pass
    return calls


@pytest.mark.parametrize('command', ['compile','parse'])
def test_offline_commands_do_not_write(command):
    assert render_hook(command=command)==[]


def test_hook_destinations_and_result_capture():
    calls=render_hook(statuses=('error','skipped'))
    assert 'prod_monitoring' in calls[0]
    merged=next(s for s in calls if 'MERGE INTO' in s)
    assert "'error'" in merged and "'skipped'" in merged
    assert "population''s check" in merged
    assert 't.invocation_id = s.invocation_id AND t.node_id = s.node_id' in merged
    assert 'WHEN MATCHED' not in merged
    for sql in calls:
        sqlglot.parse(sql,read='databricks',error_level=sqlglot.ErrorLevel.RAISE)
    assert 'dbt_test_monitoring' in render_hook(gold='dbt_test_gold')[0]


def test_monitoring_write_failure_is_not_swallowed():
    with pytest.raises(RuntimeError,match='write failed'):
        render_hook(fail_write=True)


@pytest.mark.parametrize('statuses,command,expected,project,verdict', [
    (['success','pass'],'build',2,2,'PASS'),
    (['error','skipped'],'build',2,2,'FAIL'),
    (['success','fail'],'build',2,2,'FAIL'),
    (['success','warn'],'build',2,2,'WARN'),
    (['success','skipped'],'build',2,2,'INCOMPLETE'),
    (['success'],'build',2,2,'INCOMPLETE'),
    (['pass'],'test',1,2,'PARTIAL_COMMAND'),
    (['success','pass'],'build',2,3,'PARTIAL_SELECTION'),
])
def test_summary_does_not_report_false_pass(statuses,command,expected,project,verdict):
    calls=render_hook()
    sql=next(s for s in calls if 'CREATE OR REPLACE VIEW' in s and '`dq_run_summary`' in s)
    tree=sqlglot.parse_one(sql,read='databricks');tree.set('replace',False)
    for t in tree.find_all(exp.Table):
        t.set('db',None);t.set('catalog',None)
    c=sqlite3.connect(':memory:')
    c.execute('CREATE TABLE dq_results(invocation_id TEXT,command TEXT,bronze_schema TEXT,silver_schema TEXT,gold_schema TEXT,dbt_version TEXT,run_started_at TEXT,recorded_at TEXT,expected_nodes INT,project_nodes INT,resource_type TEXT,status TEXT)')
    for i,status in enumerate(statuses):
        c.execute('INSERT INTO dq_results VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',('run-1',command,'dev_bronze','prod_silver','prod_gold','1.10.15','2026-10-22','2026-10-22',expected,project,'model' if i==0 else 'test',status))
    c.execute(tree.sql(dialect='sqlite'))
    assert c.execute('SELECT run_status FROM dq_run_summary').fetchone()[0]==verdict
