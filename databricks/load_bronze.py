"""Databricks notebook helper. Remote execution NOT tested in this deliverable.

Upload ONE committed processing-key directory (including its manifest) to a
Unity Catalog volume. Call ingest_revision with an explicit target table.
Run only one ingestion writer per target table; remote concurrency is not covered
by the local flock/SQLite ledger.
"""
import hashlib
import json
import re
from pathlib import Path


def _hash(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def ingest_revision(spark, directory, target_table, table_id):
    from delta.tables import DeltaTable
    from pyspark.sql import functions as F

    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*', target_table):
        raise ValueError('Supply catalog.schema.table using simple identifiers')
    root = Path(directory)
    if not str(root).startswith('/Volumes/'):
        raise ValueError('Use an explicit Unity Catalog volume directory')
    manifest = json.loads((root / 'manifest.json').read_text())
    files = {f['path']: f for f in manifest['files']}
    name = table_id + '.parquet'
    if name not in files or Path(name).name != name:
        raise ValueError('Requested table not in committed manifest')
    for entry in manifest['files']:
        if Path(entry['path']).name != entry['path']:
            raise ValueError('Unsafe manifest path')
        if _hash(root / entry['path']) != entry['sha256']:
            raise ValueError('Uploaded file failed SHA-256 integrity check')
    if files['original.bin']['sha256'] != manifest['file_sha256']:
        raise ValueError('Original file digest mismatch')
    df = spark.read.parquet(str(root / name))
    expected = files[name]['row_count']
    if df.count() != expected:
        raise ValueError('Uploaded row count mismatch')
    if df.filter(F.col('processing_key') != manifest['processing_key']).count():
        raise ValueError('Processing key mismatch')
    if df.filter(F.col('record_id').isNull()).count() or df.select('record_id').distinct().count() != expected:
        raise ValueError('Missing/duplicate record identifiers')
    # Create schema/table explicitly and non-destructively. Never overwrite Bronze.
    schema = '.'.join(target_table.split('.')[:2])
    spark.sql(f'CREATE SCHEMA IF NOT EXISTS {schema}')
    if not spark.catalog.tableExists(target_table):
        df.limit(0).write.format('delta').mode('append').saveAsTable(target_table)
    existing = spark.table(target_table)
    if existing.schema != df.schema:
        raise ValueError('Target schema differs; explicit schema review required')
    candidate_new = df.join(existing.select('record_id'), 'record_id', 'left_anti').count()
    (DeltaTable.forName(spark, target_table).alias('t')
       .merge(df.alias('s'), 't.record_id = s.record_id')
       .whenNotMatchedInsertAll()
       .execute())
    target_ids = spark.table(target_table).select('record_id')
    if df.join(target_ids, 'record_id', 'left_anti').count():
        raise ValueError('Post-ingestion record check failed')
    if (spark.table(target_table).filter(F.col('processing_key') == manifest['processing_key'])
            .groupBy('record_id').count().filter(F.col('count') > 1).count()):
        raise ValueError('Duplicate target identifiers detected')
    return {'processing_key': manifest['processing_key'], 'table': target_table,
            'source_rows': expected, 'candidate_new_rows': candidate_new,
            'verified': True, 'concurrency': 'single remote writer only'}

