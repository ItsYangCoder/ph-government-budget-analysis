from pondolens.common.hashing import dataset_fingerprint
import pondolens.common.config as common_config
import pondolens.ingestion.routing as ingestion_routing
'storage.databricks responsibilities for one ingestion run.'
import json
from datetime import datetime, timezone
from pathlib import Path

def log(ctx, dataset, status, count, message=None, files_loaded=0, started_at=None, rescued_rows=0):
    record = {'run_id': ctx.RUN_ID, 'dataset': dataset, 'status': status, 'rows_loaded': str(count), 'finished_at': datetime.now(timezone.utc).isoformat(), 'message': message or '', 'files_loaded': files_loaded, 'rescued_rows': rescued_rows, 'started_at': started_at}
    audit_types = {'files_loaded': ctx.LongType(), 'rescued_rows': ctx.LongType(), 'started_at': ctx.TimestampType()}
    schema = ctx.StructType([ctx.StructField(key, audit_types.get(key, ctx.StringType()), True) for key in record])
    ctx.spark.createDataFrame([tuple(record.values())], schema).write.format('delta').mode('append').option('mergeSchema', 'true').saveAsTable(f'{ctx.TARGET}.gdrive_ingestion_log')

def table_exists(ctx, table):
    """Treat a missing namespace or concurrently dropped table as absent."""
    try:
        if not ctx.spark.catalog.tableExists(table):
            return False
        ctx.spark.table(table).schema
        return True
    except Exception as exc:
        get_condition = getattr(exc, 'getCondition', None) or getattr(exc, 'getErrorClass', None)
        condition = get_condition() if get_condition else None
        if condition in {'CATALOG_NOT_FOUND', 'SCHEMA_NOT_FOUND', 'NO_SUCH_CATALOG_EXCEPTION', 'NO_SUCH_DATABASE', 'TABLE_OR_VIEW_NOT_FOUND'}:
            return False
        raise

def ensure_storage(ctx):
    """Provision Unity Catalog storage only on a load run."""
    if ctx.DRY_RUN:
        print('Dry run: catalog/schema/volume creation skipped.', flush=True)
        return
    ctx.spark.sql(f'CREATE CATALOG IF NOT EXISTS `{ctx.CATALOG}`')
    ctx.spark.sql(f'CREATE SCHEMA IF NOT EXISTS `{ctx.CATALOG}`.`{ctx.SCHEMA}`')
    ctx.spark.sql(f'CREATE VOLUME IF NOT EXISTS `{ctx.CATALOG}`.`{ctx.SCHEMA}`.`{ctx.VOLUME}`')
    ctx.dbutils.fs.ls(ctx.ROOT)

def create_context(params, spark=None, dbutils=None):
    """Initialize a fresh run; injected handles also support isolated tests."""
    from types import SimpleNamespace
    import uuid
    try:
        import openpyxl
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaIoBaseDownload
        from pyspark.sql import SparkSession, functions as F
        from pyspark.sql.types import LongType, StringType, StructField, StructType, TimestampType
    except ImportError as exc:
        raise RuntimeError('Install the project dependencies and run on Databricks Spark compute.') from exc
    custom = json.loads(params['sheet_overrides_json'])
    if not isinstance(custom, dict) or any((not isinstance(k, str) or not isinstance(v, str) for k, v in custom.items())):
        raise ValueError('sheet_overrides_json must map file IDs to sheet names')
    if spark is None:
        spark = SparkSession.builder.getOrCreate()
    if dbutils is None:
        from databricks.sdk import WorkspaceClient
        dbutils = WorkspaceClient().dbutils
    ctx = SimpleNamespace(PARAMS=dict(params), CATALOG=params['catalog'], SCHEMA=params['schema'], VOLUME=params['volume'], DRIVE_FOLDER_ID=params['drive_folder_id'], SECRET_SCOPE=params['secret_scope'], SECRET_KEY=params['secret_key'], DRY_RUN=params['dry_run'] == 'true', SELECTED_DATASET=params['dataset'], SHEET_OVERRIDES={'1vCXocazfgtHpey2wG6sTzpQFI-pBrDfF': 'Long Form', **custom}, RUN_ID=uuid.uuid4().hex, TARGET=f"{params['catalog']}.{params['schema']}", ROOT=f"/Volumes/{params['catalog']}/{params['schema']}/{params['volume']}", spark=spark, dbutils=dbutils, openpyxl=openpyxl, service_account=service_account, build=build, MediaIoBaseDownload=MediaIoBaseDownload, F=F, LongType=LongType, StringType=StringType, StructField=StructField, StructType=StructType, TimestampType=TimestampType)
    return ctx

def write_dataset(ctx, dataset, entries):
    failures = []
    started_at = datetime.now(timezone.utc)
    files_loaded = 0
    rescued_rows = 0
    table = f'{ctx.TARGET}.{common_config.identifier(dataset)}'
    count = sum((len(entry[3]) for entry in entries))
    fingerprint = dataset_fingerprint(dataset, entries)
    try:
        if table_exists(ctx, table):
            current = ctx.spark.table(table)
            if '_dataset_hash' in current.columns:
                hashes = [r[0] for r in current.select('_dataset_hash').distinct().collect()]
                if '_rescued_data' in current.columns and hashes == [fingerprint] and (current.count() == count):
                    print(f'SKIPPED {table}: unchanged source content')
                    log(ctx, dataset, 'SKIPPED', 0, files_loaded=0, started_at=started_at)
                    return []
        combined = None
        for item, payload, headers, records, sheet, digest, header_map in entries:
            extension = ingestion_routing.source_extension(item)
            path = Path(ctx.ROOT) / 'gdrive_landing' / item['id'] / (digest + extension)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
            schema = ctx.StructType([ctx.StructField(c, ctx.StringType(), True) for c in headers])
            frame = ctx.spark.createDataFrame(records, schema)
            for column, value in {'_drive_file_id': item['id'], '_source_file': item['relative_path'], '_landing_file': str(path), '_source_modified_at': item['modifiedTime'], '_source_sheet': sheet, '_content_hash': digest, '_header_map': json.dumps(header_map), '_dataset_hash': fingerprint, '_run_id': ctx.RUN_ID}.items():
                frame = frame.withColumn(column, ctx.F.lit(value).cast('string'))
            frame = frame.withColumn('_ingested_at', ctx.F.current_timestamp())
            combined = frame if combined is None else combined.unionByName(frame, allowMissingColumns=True)
        if combined.count() != count:
            raise RuntimeError(f'Pre-write row count mismatch for {table}')
        combined.write.format('delta').mode('overwrite').option('overwriteSchema', 'true').saveAsTable(table)
        files_loaded = len(entries)
        actual = ctx.spark.table(table).count()
        rescued_rows = ctx.spark.table(table).where(ctx.F.col('_rescued_data').isNotNull()).count()
        if actual != count:
            raise RuntimeError(f'Row count mismatch: expected={count}, actual={actual}')
        log(ctx, dataset, 'SUCCESS', actual, files_loaded=files_loaded, started_at=started_at, rescued_rows=rescued_rows)
        print(f'SUCCESS {table}: files={len(entries)} rows={actual}')
    except Exception as exc:
        failures.append(f'{dataset}: {exc}')
        try:
            log(ctx, dataset, 'FAILED', 0, str(exc)[:2000], files_loaded=files_loaded, started_at=started_at, rescued_rows=rescued_rows)
        except Exception as log_error:
            print(f'Log failed for {dataset}: {log_error}')
    return failures
