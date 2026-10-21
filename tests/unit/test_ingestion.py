"""Offline checks: parsing, safeguards, widgets, fingerprints and run control."""
import hashlib
import importlib.util
import io
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from pondolens.common.config import DEFAULTS, WIDGET_NAMES, parameters
from pondolens.common.hashing import dataset_fingerprint
from pondolens.ingestion import parsers, pipeline, routing, validation
from pondolens.storage import databricks


def context(**changes):
    values = dict(PARAMS=parameters([]), SHEET_OVERRIDES={}, SELECTED_DATASET='all',
                  TARGET='pondolens.dev_bronze', DRIVE_FOLDER_ID='folder', DRY_RUN=True,
                  CATALOG='pondolens', SCHEMA='dev_bronze', VOLUME='government_budget',
                  ROOT='/Volumes/pondolens/dev_bronze/government_budget')
    values.update(changes)
    return SimpleNamespace(**values)


def item(name='sample.csv', path='07_Health/hospital.csv'):
    return dict(id='file1', name=name, relative_path=path, mimeType='text/csv', modifiedTime='2026-01-01T00:00:00Z')


class IngestionTests(unittest.TestCase):
    def test_health_and_completion_routing(self):
        self.assertEqual(routing.route('07_Health/hospital.csv'), 'hospital')
        self.assertEqual(routing.route('09_Development_Indicators/04_Completion_Rate/a.csv'), 'completion_rate')
        self.assertIsNone(routing.route('unknown/file.csv'))

    def test_latest_dataset_scope(self):
        from pondolens.common.config import DATASET_NAMES
        self.assertFalse({'sector_expenditure', 'grdp', 'ched_graduates'} & set(DATASET_NAMES))
        cases = {
            '02_Sector_Expenditure/a.csv': '__excluded__',
            '04_Development_Indicators/GRDP/a.csv': '__excluded__',
            '04_Development_Indicators/Quality_Education/a.csv': '__excluded__',
            '04_Development_Indicators/GRDP_Per_Capita/a.csv': 'grdp_per_capita',
            '07_Health/doh_regulated_hospitals.csv': 'hospital',
            '03_Regional_Expenditure/2025_gaa.csv': 'regional_appropriation',
            '03_Regional_Expenditure/2025_obligations.csv': 'regional_obligations',
        }
        for source, expected in cases.items():
            self.assertEqual(routing.route(source), expected)

    def test_dependency_bootstrap(self):
        from pondolens.common.dependencies import ensure_dependencies
        with patch('importlib.util.find_spec', return_value=object()), patch('subprocess.run') as install:
            ensure_dependencies()
            install.assert_not_called()
        with patch('importlib.util.find_spec', return_value=None), patch('subprocess.run') as install:
            ensure_dependencies()
            command = install.call_args.args[0]
            self.assertEqual(command[:4], [sys.executable, '-m', 'pip', 'install'])
            self.assertIn('openpyxl>=3.1,<4', command)
            self.assertTrue(install.call_args.kwargs['check'])

    def test_csv_strings_and_blank_rows(self):
        h, rows, sheet, mapping = parsers.read_rows(context(), item(), b'Year,Hospital Count\n2021,10\n,\n')
        self.assertEqual(h, ['year', 'hospital_count', '_rescued_data'])
        self.assertEqual(rows, [('2021', '10', None)])
        self.assertEqual(mapping, {'year':'Year', 'hospital_count':'Hospital Count'})

    def test_rescued_row_preserves_source(self):
        _, rows, _, _ = parsers.read_rows(context(), item(), b'year,count\n2021,3,extra\n')
        self.assertEqual(rows[0][:2], (None,None))
        self.assertEqual(json.loads(rows[0][-1])['original_values'], ['2021','3','extra'])

    def test_completion_header_offset(self):
        source=item(path='04_Development_Indicators/Completion_Rate/a.csv')
        h, rows, _, _ = parsers.read_rows(context(), source, b'PSA report\nIndicator,Geolocation,Level of Education,Sex,2021\nCompletion,NCR,Elementary,Both,98\n')
        self.assertEqual(h[0], 'indicator')
        self.assertEqual(rows[0][-2], '98')

    def test_header_collision(self):
        with self.assertRaises(ValueError):parsers.clean_header(['Region Name','Region-Name'])
        with self.assertRaises(ValueError):parsers.clean_header(['_run_id'])

    def test_row_limit(self):
        ctx=context();ctx.PARAMS['max_total_rows']=1
        with self.assertRaises(ValueError):parsers.bounded_rows(ctx, range(22))

    def test_replacement_protection(self):
        with self.assertRaisesRegex(ValueError,'source files missing'):
            validation.validate_replacement(context(), ['a'], [], ['year'], ['year'])
        with self.assertRaisesRegex(ValueError,'columns would be removed'):
            validation.validate_replacement(context(), ['a'], ['a'], ['year','region'], ['year'])
        ctx=context();ctx.PARAMS['allow_source_removal']='true'
        validation.validate_replacement(ctx, ['a'], [], ['year'], ['year'])

    def test_parameters(self):
        self.assertEqual(parameters([])['dataset'],'all')
        self.assertEqual(parameters(['--dataset','hospital'])['max_file_mb'],50)
        with self.assertRaises(SystemExit):parameters(['--catalog','bad.name'])

    def test_geojson_and_duplicate(self):
        feature={'type':'Feature','properties':{'adm1_psgc':'1','adm1_en':'Region'},'geometry':{'type':'Polygon','coordinates':[[[0,0],[1,0],[0,0]]]}}
        payload={'type':'FeatureCollection','features':[feature]}
        _, rows, _, _=parsers.read_geojson(json.dumps(payload).encode())
        self.assertEqual(rows[0][0],'1');self.assertIsNone(rows[0][-1])
        payload['features'].append(feature)
        with self.assertRaises(ValueError):parsers.read_geojson(json.dumps(payload).encode())

    def test_fingerprint_order(self):
        entry=(item(),b'x',['year'],[('2021',)],None,hashlib.sha256(b'x').hexdigest(),{'year':'Year'})
        self.assertEqual(dataset_fingerprint('health',[entry]),dataset_fingerprint('health',[entry]))
        changed=list(entry);changed[5]='changed'
        self.assertNotEqual(dataset_fingerprint('health',[entry]),dataset_fingerprint('health',[tuple(changed)]))

    def test_dry_run_no_storage_writes(self):
        ctx=context(spark=SimpleNamespace(sql=lambda _:self.fail('dry run wrote SQL')))
        databricks.ensure_storage(ctx)

    def test_storage_order(self):
        calls=[];ctx=context(DRY_RUN=False,spark=SimpleNamespace(sql=calls.append),dbutils=SimpleNamespace(fs=SimpleNamespace(ls=lambda path:calls.append(path))))
        databricks.ensure_storage(ctx)
        self.assertEqual(len(calls),4)
        self.assertTrue(calls[0].startswith('CREATE CATALOG IF NOT EXISTS'))
        self.assertTrue(calls[2].startswith('CREATE VOLUME IF NOT EXISTS'))

    def test_widgets(self):
        path=Path(__file__).resolve().parents[2]/'platform/databricks/runners/run_ingestion.py'
        spec=importlib.util.spec_from_file_location('runner',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        class Widgets:
            def __init__(self):self.values={'auth_mode':'file'}
            def get(self,k):return self.values[k]
            def remove(self,k):del self.values[k]
            def text(self,k,v):self.values.setdefault(k,v)
            def dropdown(self,k,v,options):self.values.setdefault(k,v)
        widgets=Widgets();widgets.values['dataset']='hospital'
        result=module.widget_parameters(SimpleNamespace(widgets=widgets))
        self.assertEqual(set(widgets.values),set(WIDGET_NAMES))
        self.assertEqual(result['dataset'],'hospital')

    def test_dry_run_pipeline(self):
        request=SimpleNamespace(execute=lambda **kwargs:{'name':'sources'})
        drive=SimpleNamespace(files=lambda:SimpleNamespace(get=lambda **kwargs:request))
        ctx=context(load_credentials=None,build=lambda *a,**k:drive)
        sources=[item()]
        with patch('pondolens.ingestion.google_drive.load_credentials',return_value=object()),patch('pondolens.ingestion.google_drive.walk',return_value=iter(sources)),patch('pondolens.ingestion.google_drive.download',return_value=b'year,count\n2021,3\n'),patch('pondolens.ingestion.validation.preflight') as preflight,patch('pondolens.storage.databricks.write_dataset') as write:
            pipeline.main(ctx)
            preflight.assert_called_once();write.assert_not_called()


if __name__=='__main__':unittest.main()
