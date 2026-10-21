"""ingestion.validation responsibilities for one ingestion run."""
from pondolens.common.config import DATASET_NAMES
import pondolens.common.config as common_config
import pondolens.ingestion.google_drive as ingestion_google_drive
import pondolens.ingestion.routing as ingestion_routing
import pondolens.ingestion.validation as ingestion_validation
import pondolens.storage.databricks as storage_databricks

def validate_replacement(ctx, previous_ids, current_ids, previous_columns, new_columns):
    """Block accidental data/schema loss before snapshot replacement."""
    removed = set(previous_ids) - set(current_ids)
    if removed and ctx.PARAMS['allow_source_removal'] != 'true':
        raise ValueError(f'Existing source files missing from Drive: {sorted(removed)}. Restore them or explicitly set --allow_source_removal true.')
    removed_columns = {c for c in previous_columns if not c.startswith('_')} - set(new_columns)
    if removed_columns and ctx.PARAMS['allow_schema_removal'] != 'true':
        raise ValueError(f'Source columns would be removed: {sorted(removed_columns)}. Review or explicitly set --allow_schema_removal true.')

def source_snapshot(ctx, sources):
    return sorted(((s['id'], s['relative_path'], s['modifiedTime'], s['mimeType']) for s in sources if ctx.SELECTED_DATASET == 'all' or ingestion_routing.route(s['relative_path']) == ctx.SELECTED_DATASET))

def preflight(ctx, plans, sources, drive):
    """Validate the full plan before writing landing files or Delta tables."""
    if ingestion_validation.source_snapshot(ctx, sources) != ingestion_validation.source_snapshot(ctx, list(ingestion_google_drive.walk(drive, ctx.DRIVE_FOLDER_ID))):
        raise RuntimeError('Drive inventory changed during validation; rerun with stable source files')
    for dataset, entries in plans.items():
        table = f'{ctx.TARGET}.{common_config.identifier(dataset)}'
        columns = {c for entry in entries for c in entry[2]}
        current_ids = {entry[0]['id'] for entry in entries}
        if dataset == 'region_boundaries':
            codes = [str(row[0]).zfill(10) for entry in entries for row in entry[3]]
            if len(codes) != len(set(codes)):
                raise ValueError('Duplicate region boundaries across files; select one boundary version per dataset')
        if storage_databricks.table_exists(ctx, table):
            previous = ctx.spark.table(table)
            if '_drive_file_id' not in previous.columns:
                raise ValueError(f'{table}: missing source lineage; review before replacing')
            ids = [r[0] for r in previous.select('_drive_file_id').distinct().collect()]
            ingestion_validation.validate_replacement(ctx, ids, current_ids, previous.columns, columns)
    if ctx.SELECTED_DATASET == 'all' and ctx.PARAMS['allow_source_removal'] != 'true':
        for dataset in set(DATASET_NAMES) - set(plans):
            table = f'{ctx.TARGET}.{common_config.identifier(dataset)}'
            if storage_databricks.table_exists(ctx, table) and ctx.spark.table(table).limit(1).count():
                raise ValueError(f'No Drive files found for existing dataset {dataset}; restore sources, select one dataset, or review --allow_source_removal true')
