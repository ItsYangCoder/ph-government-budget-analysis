"""ingestion.routing responsibilities for one ingestion run."""
import re
from pathlib import Path
from pondolens.common.config import SHEET_MIME
import pondolens.ingestion.routing as ingestion_routing

def folder_label(value):
    """Ignore numeric prefixes so folder renumbering does not break routing."""
    return re.sub('^\\d+[_ -]*', '', value.strip().lower())

def route(relative_path):
    """Route known folder labels; accept new years without code changes."""
    parts = relative_path.lower().split('/')
    root, name = (ingestion_routing.folder_label(parts[0]), parts[-1])
    direct = {'agency_actuals': 'agency_actuals', 'sector_expenditure': '__excluded__', 'population': 'population'}
    if root in direct:
        return direct[root]
    if root == 'regional_expenditure':
        if 'gaa' in name:
            return 'regional_appropriation'
        if 'obligation' in name:
            return 'regional_obligations'
    if root == 'health' and name.startswith(('doh_regulated_hospitals', 'hospital')):
        return 'hospital'
    if root == 'development_indicators' and len(parts) > 2:
        return {'quality_education': '__excluded__', 'unemployment_rate': 'unemployment_rate', 'poverty_incidence': 'poverty_incidence', 'service_access': 'service_access', 'grdp': '__excluded__', 'grdp_capita': 'grdp_per_capita', 'grdp_per_capita': 'grdp_per_capita', 'student_completion_rate': 'completion_rate', 'completion_rate': 'completion_rate'}.get(ingestion_routing.folder_label(parts[1]))
    if root in {'geographic_reference', 'geographic_reference(optional)'}:
        if name.endswith(('.geojson', '.json')):
            return 'region_boundaries'
    return None

def source_extension(item):
    if item['mimeType'] == SHEET_MIME:
        return '.xlsx'
    return Path(item['name'].lower()).suffix

def supported_source(item, dataset):
    extension = ingestion_routing.source_extension(item)
    if dataset == 'region_boundaries':
        return extension in {'.geojson', '.json'}
    return extension in {'.csv', '.xlsx', '.xlsm'}
