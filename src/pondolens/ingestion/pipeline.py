"""ingestion.pipeline responsibilities for one ingestion run."""
import hashlib
from collections import defaultdict
import pondolens.ingestion.google_drive as ingestion_google_drive
import pondolens.ingestion.parsers as ingestion_parsers
import pondolens.ingestion.routing as ingestion_routing
import pondolens.ingestion.validation as ingestion_validation
import pondolens.storage.databricks as storage_databricks

def main(ctx):
    print(f'Starting ingestion; dataset={ctx.SELECTED_DATASET}; dry_run={ctx.DRY_RUN}', flush=True)
    credentials = ingestion_google_drive.load_credentials(ctx)
    drive = ctx.build('drive', 'v3', credentials=credentials, cache_discovery=False)
    folder = drive.files().get(fileId=ctx.DRIVE_FOLDER_ID, fields='id,name', supportsAllDrives=True).execute(num_retries=3)
    print(f"Connected! Source folder: {folder['name']}", flush=True)
    sources = list(ingestion_google_drive.walk(drive, ctx.DRIVE_FOLDER_ID))
    plans = defaultdict(list)
    errors = []
    total_bytes = total_rows = 0
    for item in sources:
        dataset = ingestion_routing.route(item['relative_path'])
        if dataset == '__excluded__':
            continue
        if ctx.SELECTED_DATASET != 'all' and dataset != ctx.SELECTED_DATASET:
            continue
        supported = ingestion_routing.supported_source(item, dataset)
        if not dataset or not supported:
            errors.append(f"Unmapped/unsupported source: {item['relative_path']}")
            continue
        try:
            payload = ingestion_google_drive.download(ctx, drive, item)
            total_bytes += len(payload)
            if total_bytes > ctx.PARAMS['max_total_mb'] * 1024 * 1024:
                raise ValueError('Source bytes exceed max_total_mb; select one dataset per run')
            headers, records, sheet, header_map = ingestion_parsers.read_rows(ctx, item, payload)
            total_rows += len(records)
            if total_rows > ctx.PARAMS['max_total_rows']:
                raise ValueError('Source records exceed max_total_rows; select one dataset per run')
            digest = hashlib.sha256(payload).hexdigest()
            plans[dataset].append((item, payload, headers, records, sheet, digest, header_map))
            print(f"VALID {dataset}: {item['relative_path']} rows={len(records)} tab={sheet}")
        except Exception as exc:
            errors.append(f"{item['relative_path']}: {exc}")
            if total_bytes > ctx.PARAMS['max_total_mb'] * 1024 * 1024 or total_rows > ctx.PARAMS['max_total_rows']:
                break
    if not sources:
        errors.append('No sources found in Drive folder')
    if not plans and (not errors):
        errors.append(f'No files found for selected dataset: {ctx.SELECTED_DATASET}')
    if errors:
        raise ValueError('Validation failed; no tables written:\n' + '\n'.join(errors))
    ingestion_validation.preflight(ctx, plans, sources, drive)
    file_count = sum((len(entries) for entries in plans.values()))
    print(f'Plan: {file_count} files -> {len(plans)} tables; dry_run={ctx.DRY_RUN}')
    if ctx.DRY_RUN:
        storage_databricks.ensure_storage(ctx)
        return
    storage_databricks.ensure_storage(ctx)
    failures = []
    for dataset, entries in sorted(plans.items()):
        failures.extend(storage_databricks.write_dataset(ctx, dataset, entries))
    if failures:
        raise RuntimeError('Some datasets failed; rerun after fixing:\n' + '\n'.join(failures))
    print(f'Completed run {ctx.RUN_ID}. Log: {ctx.TARGET}.gdrive_ingestion_log')

def run(params, *, spark=None, dbutils=None):
    """Execute one run using independent runtime state."""
    ctx = storage_databricks.create_context(params, spark=spark, dbutils=dbutils)
    main(ctx)
    return ctx.RUN_ID
