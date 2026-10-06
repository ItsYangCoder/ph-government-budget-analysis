"""Parquet files plus checksummed manifests for atomic, recoverable publication."""
import json
import os
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

from .common import canonical, file_hash


SCHEMA = pa.schema([
    (name, typ) for name, typ in [
        ('record_id', pa.string()), ('source_id', pa.string()),
        ('source_file_name', pa.string()), ('source_location', pa.string()),
        ('source_file_sha256', pa.string()), ('processing_key', pa.string()),
        ('batch_id', pa.string()), ('run_id', pa.string()),
        ('ingested_at_utc', pa.string()), ('extractor_version', pa.string()),
        ('config_hash', pa.string()), ('table_id', pa.string()),
        ('source_sheet', pa.string()), ('source_page', pa.int64()),
        ('source_row', pa.int64()), ('source_record_locator', pa.string()),
        ('raw_value_json', pa.string()), ('parsed_numeric', pa.float64()),
        ('dimensions_json', pa.string()), ('quality_flags', pa.list_(pa.string())),
    ]
])


def fsync_file(path):
    with Path(path).open('rb') as f:
        os.fsync(f.fileno())


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_json(path, value):
    with Path(path).open('w', encoding='utf-8') as f:
        f.write(canonical(value) + '\n')
        f.flush()
        os.fsync(f.fileno())


def build_output(stage, records, metadata, checks, manifest):
    stage = Path(stage)
    files = []
    for table_id in sorted({r['table_id'] for r in records}):
        rows = [r for r in records if r['table_id'] == table_id]
        path = stage / f'{table_id}.parquet'
        pq.write_table(pa.Table.from_pylist(rows, schema=SCHEMA), path, compression='snappy')
        fsync_file(path)
        files.append({'path': path.name, 'sha256': file_hash(path),
                      'kind': 'parquet', 'row_count': len(rows)})
    for name, value in [('metadata.json', metadata), ('validation.json', checks)]:
        write_json(stage / name, value)
        files.append({'path': name, 'sha256': file_hash(stage / name), 'kind': 'json'})
    fsync_file(stage / 'original.bin')
    files.append({'path': 'original.bin', 'sha256': file_hash(stage / 'original.bin'), 'kind': 'original'})
    manifest = {**manifest, 'files': files, 'row_count': len(records),
                'flagged_records': sum(bool(r['quality_flags']) for r in records)}
    write_json(stage / 'manifest.json', manifest)
    fsync_dir(stage)
    return manifest


def verify_output(directory, expected_key):
    """Check actual bytes and row counts, not just existence or SQLite status."""
    directory = Path(directory)
    try:
        m = json.loads((directory / 'manifest.json').read_text())
        if m['processing_key'] != expected_key or not m['files']:
            return None
        required = {'metadata.json', 'validation.json', 'original.bin'}
        if not required.issubset({f['path'] for f in m['files']}):
            return None
        total = 0
        for entry in m['files']:
            if Path(entry['path']).name != entry['path']:
                return None
            path = directory / entry['path']
            if not path.is_file() or file_hash(path) != entry['sha256']:
                return None
            if entry['kind'] == 'parquet':
                n = pq.ParquetFile(path).metadata.num_rows
                if n != entry['row_count']:
                    return None
                total += n
        if total != m['row_count'] or total == 0:
            return None
        original = next(f for f in m['files'] if f['kind'] == 'original')
        if original['sha256'] != m['file_sha256']:
            return None
        return m
    except (OSError, ValueError, KeyError, StopIteration, pa.ArrowException):
        return None

