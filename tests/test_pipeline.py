import copy
import json
import multiprocessing
import sqlite3
import subprocess
import sys
from pathlib import Path

import pyarrow.parquet as pq
import pytest

from pondolens.common import file_hash
from pondolens.pipeline import run_pipeline
from conftest import write_xlsx


def run(s, batch='first', **kwargs):
    return run_pipeline(s['config'], s['input'], s['output'], batch, **kwargs)


def result(s):
    return run(s)['results'][0]


def test_first_and_rerun(source):
    a = result(source)
    assert a['status'] == 'PROCESSED' and a['row_count'] == 4
    p = Path(a['output_dir']) / 'current.parquet'
    before = file_hash(p)
    b = run(source, 'new-batch')['results'][0]
    assert b['status'] == 'SKIPPED' and file_hash(p) == before
    assert len(list(source['output'].glob('committed/*/*'))) == 1


def test_renamed_identical_records_sighting(source):
    a = result(source)
    source['path'].rename(source['input'] / 'renamed.xlsx')
    assert result(source)['status'] == 'SKIPPED'
    with sqlite3.connect(source['output'] / 'state.sqlite') as db:
        assert db.execute('SELECT count(*) FROM sightings').fetchone()[0] == 2


def test_new_contents_same_filename(source):
    a = result(source)
    source['cells']['E5'] = 14.0
    write_xlsx(source['path'], source['cells'])
    b = result(source)
    assert b['status'] == 'PROCESSED' and b['processing_key'] != a['processing_key']
    assert len(list(source['output'].glob('committed/*/*'))) == 2


def test_new_year_by_configuration(source):
    result(source)
    source['cells']['E4'] = 2026
    write_xlsx(source['path'], source['cells'])
    source['config']['sources'][0]['years'][1]['year'] = 2026
    assert result(source)['status'] == 'PROCESSED'


@pytest.mark.parametrize('cell,value', [('A1', 'Unsupported title'), ('B5', 'New boundary'), ('D4', 1900)])
def test_layout_rejected(source, cell, value):
    source['cells'][cell] = value
    write_xlsx(source['path'], source['cells'])
    r = result(source)
    assert r['status'] == 'FAILED' and Path(r['quarantine_dir']).is_dir()
    assert not list(source['output'].glob('committed/*/*'))


def test_configuration_change(source):
    a = result(source)
    source['config']['sources'][0]['quality_flags'] = ['reviewed_note']
    b = result(source)
    assert b['status'] == 'PROCESSED' and a['processing_key'] != b['processing_key']


def test_extractor_version_change(source):
    a = result(source)
    b = run(source, extractor_version='0.2.0')['results'][0]
    assert b['status'] == 'PROCESSED' and a['processing_key'] != b['processing_key']


@pytest.mark.parametrize('point,expected', [('before_publish', 'PROCESSED'), ('after_publish', 'RECOVERED')])
def test_interrupted_publication_recovery(source, point, expected):
    def crash(where):
        if where == point:
            raise SystemExit('simulated process interruption')
    with pytest.raises(SystemExit):
        run(source, fault=crash)
    r = result(source)
    assert r['status'] == expected
    assert len(list(source['output'].glob('committed/*/*'))) == 1
    assert result(source)['status'] == 'SKIPPED'


def test_failed_attempt_retries(source):
    def fail(where):
        raise RuntimeError('simulated write failure')
    assert run(source, fault=fail)['results'][0]['status'] == 'FAILED'
    assert result(source)['status'] == 'PROCESSED'


@pytest.mark.parametrize('corrupt', [False, True])
def test_missing_or_corrupted_output_rebuilt(source, corrupt):
    a = result(source)
    p = Path(a['output_dir']) / 'current.parquet'
    if corrupt:
        p.write_bytes(b'corrupted')
    else:
        p.unlink()
    assert result(source)['status'] == 'PROCESSED'
    assert pq.read_table(p).num_rows == 4
    assert list(source['output'].glob('quarantine/corrupt-*'))


def _worker(s, queue):
    try:
        queue.put(result(s)['status'])
    except Exception as e:
        queue.put(repr(e))


def test_concurrent_attempts(source):
    ctx = multiprocessing.get_context('spawn')
    q = ctx.Queue()
    workers = [ctx.Process(target=_worker, args=(source, q)) for _ in range(2)]
    for w in workers:
        w.start()
    states = [q.get(timeout=30) for _ in workers]
    for w in workers:
        w.join(timeout=30)
        assert w.exitcode == 0
    assert sorted(states) == ['PROCESSED', 'SKIPPED']


def test_blanks_zeros_dashes_errors(source):
    source['config']['sources'][0]['controls'] = []
    source['cells'].update(D5=None, E5=0, D6='-', E6='#N/A')
    write_xlsx(source['path'], source['cells'])
    r = result(source)
    records = pq.read_table(Path(r['output_dir']) / 'current.parquet').to_pylist()
    by = {r['source_record_locator']: r for r in records}
    assert by['Capita!D5']['parsed_numeric'] is None
    assert by['Capita!E5']['parsed_numeric'] == 0
    assert 'source_dash_undefined' in by['Capita!D6']['quality_flags']
    assert 'source_error' in by['Capita!E6']['quality_flags']
    assert json.loads(by['Capita!E6']['raw_value_json'])['value'] == '#N/A'


def test_control_failure_quarantined(source):
    source['config']['sources'][0]['controls'][0]['expected'] = 99
    assert result(source)['status'] == 'FAILED'


def test_stable_record_ids_for_identical_values(source):
    r = result(source)
    records = pq.read_table(Path(r['output_dir']) / 'current.parquet').to_pylist()
    assert len({r['record_id'] for r in records}) == 4


def test_missing_source_reported(source):
    source['path'].unlink()
    assert result(source)['status'] == 'MISSING'


def test_discovery_path_change_does_not_reprocess(source):
    result(source)
    source['config']['sources'][0]['glob'] = 'source*.xlsx'
    assert result(source)['status'] == 'SKIPPED'


def test_cli_persists_state_across_processes(source):
    config = source['input'].parent / 'config.json'
    config.write_text(json.dumps(source['config']))
    cmd = [sys.executable, '-m', 'pondolens.cli', '--config', str(config),
           '--input-root', str(source['input']), '--output-root', str(source['output']),
           '--batch-id', 'process-test']
    a = subprocess.run(cmd, capture_output=True, text=True, check=True)
    b = subprocess.run(cmd, capture_output=True, text=True, check=True)
    assert json.loads(a.stdout)['counts']['PROCESSED'] == 1
    assert json.loads(b.stdout)['counts']['SKIPPED'] == 1
