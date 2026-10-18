"""Exercise table writes and unchanged reruns without a Databricks connection."""
import hashlib
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from pondolens.common.hashing import dataset_fingerprint
from pondolens.storage import databricks


class Frame:
    def __init__(self, rows):
        self.rows=rows; self.columns=['year','_rescued_data']; self.values={}; self.options={}
        self.write=self
    def withColumn(self,k,v):
        if k not in self.columns:self.columns.append(k)
        self.values[k]=v
        return self
    def count(self):return len(self.rows)
    def where(self,*args):return SimpleNamespace(count=lambda:0)
    def format(self,x):self.format_name=x;return self
    def mode(self,x):self.mode_name=x;return self
    def option(self,k,v):self.options[k]=v;return self
    def saveAsTable(self,table):self.table_name=table
    def select(self,*args):return SimpleNamespace(distinct=lambda:SimpleNamespace(collect=lambda:[(self.values['_dataset_hash'],)]))


class StorageTests(unittest.TestCase):
    def test_write_then_unchanged_rerun(self):
        payload=b'year\n2021\n';digest=hashlib.sha256(payload).hexdigest()
        item=dict(id='file1',name='health.csv',relative_path='07_Health/hospital.csv',mimeType='text/csv',modifiedTime='2026-01-01')
        entries=[(item,payload,['year','_rescued_data'],[('2021',None)],None,digest,{'year':'year'})]
        frame=Frame(entries[0][3])
        functions=SimpleNamespace(lit=lambda v:SimpleNamespace(cast=lambda _:v),current_timestamp=lambda:'timestamp',col=lambda _:SimpleNamespace(isNotNull=lambda:True))
        with tempfile.TemporaryDirectory() as directory:
            ctx=SimpleNamespace(TARGET='pondolens.dev_bronze',ROOT=directory,RUN_ID='run1',F=functions,
                StructType=lambda v:v,StructField=lambda *args:args,StringType=lambda:'string',
                spark=SimpleNamespace(createDataFrame=lambda *args:frame,table=lambda _:frame))
            with patch.object(databricks,'table_exists',return_value=False),patch.object(databricks,'log') as log:
                self.assertEqual(databricks.write_dataset(ctx,'hospital',entries),[])
                self.assertEqual(log.call_args.args[2],'SUCCESS')
            self.assertEqual(frame.mode_name,'overwrite')
            self.assertEqual(frame.options,{'overwriteSchema':'true'})
            self.assertEqual(frame.values['_dataset_hash'],dataset_fingerprint('hospital',entries))
            self.assertEqual(frame.values['_source_file'],item['relative_path'])
            self.assertEqual(Path(frame.values['_landing_file']).read_bytes(),payload)
            required={'_drive_file_id','_source_file','_landing_file','_source_modified_at','_source_sheet','_content_hash','_header_map','_dataset_hash','_run_id','_ingested_at','_rescued_data'}
            self.assertTrue(required.issubset(frame.columns))
            with patch.object(databricks,'table_exists',return_value=True),patch.object(databricks,'log') as log,patch.object(Path,'write_bytes',side_effect=AssertionError('unchanged data must not write')):
                self.assertEqual(databricks.write_dataset(ctx,'hospital',entries),[])
                self.assertEqual(log.call_args.args[2],'SKIPPED')

    def test_write_failure_logged(self):
        ctx=SimpleNamespace(TARGET='pondolens.dev_bronze')
        with patch.object(databricks,'table_exists',side_effect=RuntimeError('permission denied')),patch.object(databricks,'log') as log:
            result=databricks.write_dataset(ctx,'health',[])
            self.assertIn('permission denied',result[0])
            self.assertEqual(log.call_args.args[2],'FAILED')

if __name__=='__main__':unittest.main()
