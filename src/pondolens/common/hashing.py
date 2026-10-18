"""Stable dataset fingerprints; serialization matches the original script."""
import hashlib
import json
from pondolens.common.config import SHEET_MIME, PIPELINE_VERSION

def dataset_fingerprint(dataset, entries):
    return hashlib.sha256(json.dumps([(entry[0]['id'], entry[0]['relative_path'], hashlib.sha256(json.dumps({'headers': entry[2], 'records': entry[3], 'sheet': entry[4], 'header_map': entry[6]}, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')).hexdigest() if entry[0]['mimeType'] == SHEET_MIME else entry[5], entry[4]) for entry in sorted(entries, key=lambda e: e[0]['id'])] + [PIPELINE_VERSION + '-geojson-1' if dataset == 'region_boundaries' else PIPELINE_VERSION], sort_keys=True).encode()).hexdigest()
