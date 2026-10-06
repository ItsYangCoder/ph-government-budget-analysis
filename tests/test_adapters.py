import copy
import json

import pyarrow.parquet as pq
import pytest

from conftest import write_xlsx
from pondolens.adapters import Extraction, population
from pondolens.common import ExtractionError
from pondolens.pdf_adapters import numeric_token, sector_text, validate_continuation
from pondolens.pipeline import run_pipeline


def test_agency_raw_cells_with_merged_header(source):
    src = source['config']['sources'][0]
    src.update(adapter='excel_cells', ranges=['A1:E6'], expected_record_count=30)
    write_xlsx(source['path'], source['cells'], merges=['B2:C2'])
    r = run_pipeline(source['config'],source['input'],source['output'],'raw')['results'][0]
    assert r['status'] == 'PROCESSED', r
    rows = pq.read_table(r['output_dir']+'/raw_cells.parquet').to_pylist()
    assert len(rows) == 30
    assert next(x for x in rows if x['source_record_locator']=='Capita!C2')['parsed_numeric'] is None


def test_pdf_continuation_checks_labels_and_counts():
    a = [('Department A',[]),('GRAND TOTAL',[])]
    validate_continuation(a, [('Department A',[]),('GRAND TOTAL',[])],2)
    with pytest.raises(ExtractionError):
        validate_continuation(a,[('Department B',[]),('GRAND TOTAL',[])],2)
    with pytest.raises(ExtractionError):
        validate_continuation(a,a[:1],2)


def test_pdf_tokens_preserve_raw_and_do_not_guess_dash():
    assert numeric_token('1 ,234,567') == (1234567.0, [])
    assert numeric_token('-') == (None,['source_dash_undefined'])
    with pytest.raises(ExtractionError):
        numeric_token('')


def test_sector_controls():
    cfg={'expected_rows':2,'row_labels':['SECTOR A','GRAND TOTAL'],'parent_labels':['SECTOR A'],
         'periods':[{'year':2024,'status':'Actual'},{'year':2025,'status':'Program'},
                    {'year':2026,'status':'Proposed'}],'unit':'million PHP','grand_total':10}
    e=Extraction()
    sector_text('SECTOR A 10 11 12 100 100 100\nGRAND TOTAL 10 11 12 100 100 100',cfg,e)
    assert len(e.records)==12
    assert json.loads(e.records[1]['dimensions_json'])['reporting_status']=='Program'
    with pytest.raises(ExtractionError):
        sector_text('SECTOR A 9 11 12 100 100 100\nGRAND TOTAL 10 11 12 100 100 100',
                    {**cfg,'tolerance':0},Extraction())


def test_population_layout_and_preservation(tmp_path):
    cells={'A1':'Population','A3':'Both sexes','B3':'Male','C3':'Female',
           'A2':'01 July 2024','D5':'PHILIPPINES','D6':'Total','D7':'0 - 4',
           'D8':'Region A','D9':'Total','D10':'0 - 4',
           'A6':100,'B6':50,'C6':50,'A7':20,'B7':10,'C7':10,
           'A9':100,'B9':50,'C9':50,'A10':20,'B10':10,'C10':10}
    p=tmp_path/'pop.xlsx';write_xlsx(p,cells,sheet='Population')
    cfg={'sheet':'Population','blocks':{'first_heading':5,'stride':3,'count':2,'data_end':10},
         'label_col':4,'date_header_row':2,'sex_header_row':3,'sexes':['Both sexes','Male','Female'],
         'years':[{'year':2024,'start_col':1,'date_regex':'01 July 2024'}],
         'ages':['Total','0 - 4'],'region_labels':['PHILIPPINES','Region A'],'unit':'persons',
         'expected_record_count':12,'controls':[{'cell':'A6','expected':100}]}
    e=population(p,cfg);assert len(e.records)==12
    cells['D9']='Unknown';write_xlsx(p,cells,sheet='Population')
    with pytest.raises(ExtractionError):population(p,cfg)
