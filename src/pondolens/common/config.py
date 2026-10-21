"""Defaults and parameter validation; no platform initialization."""
import argparse
import re
import sys
DATASET_NAMES = ['agency_actuals', 'regional_appropriation', 'regional_obligations', 'population', 'unemployment_rate', 'poverty_incidence', 'service_access', 'grdp_per_capita', 'completion_rate', 'region_boundaries', 'hospital']
DEFAULTS = {'catalog': 'pondolens', 'schema': 'dev_bronze', 'volume': 'government_budget', 'drive_folder_id': '1L_kvzPjQE60GjUvthLuwxbC3xKevHsoB', 'auth_mode': 'secret', 'service_account_path': '', 'secret_scope': 'pondolens', 'secret_key': 'gdrive-service-account', 'dataset': 'all', 'dry_run': 'true', 'sheet_overrides_json': '{}', 'allow_source_removal': 'false', 'allow_schema_removal': 'false', 'max_file_mb': '50', 'max_total_mb': '200', 'max_total_rows': '500000'}
WIDGET_NAMES = ('catalog', 'schema', 'volume', 'drive_folder_id', 'secret_scope', 'secret_key', 'dataset', 'dry_run', 'sheet_overrides_json')
FOLDER_MIME = 'application/vnd.google-apps.folder'
SHEET_MIME = 'application/vnd.google-apps.spreadsheet'
XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
PIPELINE_VERSION = 'gdrive-snapshot-1'

def identifier(value):
    if not re.fullmatch('[A-Za-z_][A-Za-z0-9_]*', value):
        raise ValueError(f'Invalid identifier: {value!r}')
    return value

def parameters(argv=None, widget_provider=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name, default in DEFAULTS.items():
        parser.add_argument(f'--{name}', default=default)
    args = list(sys.argv[1:] if argv is None else argv)
    has_cli = any((arg.split('=', 1)[0] in {f'--{name}' for name in DEFAULTS} for arg in args))
    if argv is not None or has_cli or '--help' in args or ('-h' in args):
        result = vars(parser.parse_args(args))
    else:
        result = widget_provider() if widget_provider is not None else vars(parser.parse_args(args))
    for name in ('dry_run', 'allow_source_removal', 'allow_schema_removal'):
        if result[name] not in {'true', 'false'}:
            parser.error(f'{name} must be true or false')
    if result['auth_mode'] not in {'secret', 'file'}:
        parser.error('auth_mode must be secret or file')
    if result['dataset'] not in ['all'] + DATASET_NAMES:
        parser.error('Unknown dataset parameter')
    if not re.fullmatch('[A-Za-z0-9_-]+', result['drive_folder_id']):
        parser.error('drive_folder_id must be a folder ID, not a URL')
    for name in ('catalog', 'schema', 'volume'):
        try:
            identifier(result[name])
        except ValueError as exc:
            parser.error(str(exc))
    for name in ('max_file_mb', 'max_total_mb', 'max_total_rows'):
        try:
            result[name] = int(result[name])
        except ValueError:
            parser.error(f'{name} must be a positive integer')
        if result[name] <= 0:
            parser.error(f'{name} must be a positive integer')
    return result
