"""ingestion.parsers responsibilities for one ingestion run."""
import csv
import io
import json
import re
import pondolens.ingestion.parsers as ingestion_parsers
import pondolens.ingestion.routing as ingestion_routing

def read_geojson(payload):
    """Preserve each feature and geometry as JSON strings in Bronze."""
    data = json.loads(payload.decode('utf-8-sig'))
    if not isinstance(data, dict) or data.get('type') != 'FeatureCollection':
        raise ValueError('Expected a GeoJSON FeatureCollection')
    features = data.get('features')
    if not isinstance(features, list) or not features:
        raise ValueError('GeoJSON has no features')
    headers = ['adm1_psgc', 'adm1_en', 'geometry_json', 'properties_json', 'feature_json', '_rescued_data']
    records, seen = ([], set())
    for number, feature in enumerate(features, 1):
        if not isinstance(feature, dict) or feature.get('type') != 'Feature':
            raise ValueError(f'Invalid GeoJSON feature {number}')
        properties = feature.get('properties')
        geometry = feature.get('geometry')
        if not isinstance(properties, dict):
            raise ValueError(f'Missing properties at feature {number}')
        if not isinstance(geometry, dict) or geometry.get('type') not in {'Polygon', 'MultiPolygon'} or (not geometry.get('coordinates')):
            raise ValueError(f'Missing polygon geometry at feature {number}')
        code, name = (properties.get('adm1_psgc'), properties.get('adm1_en'))
        if isinstance(code, bool) or not re.fullmatch('\\d{1,10}', str(code)) or (not isinstance(name, str)) or (not name.strip()):
            raise ValueError(f'Missing/invalid region code or name at feature {number}')
        key = str(code).zfill(10)
        if key in seen:
            raise ValueError(f'Duplicate region boundary: {code}')
        seen.add(key)
        encode = lambda value: json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':'))
        records.append((str(code), name, encode(geometry), encode(properties), encode(feature), None))
    return (headers, records, None, dict(zip(headers[:-1], ['properties.adm1_psgc', 'properties.adm1_en', 'geometry', 'properties', 'feature'])))

def clean_header(row):
    result = []
    for index, value in enumerate(row):
        label = str(value).strip() if value is not None else ''
        if label.startswith('_'):
            raise ValueError(f'Reserved source header: {label}')
        label = re.sub('[^A-Za-z0-9_]', '_', label).strip('_').lower()
        label = label or f'source_column_{index + 1}'
        if label[0].isdigit():
            label = 'c_' + label
        if label.startswith('_') or label in result:
            raise ValueError(f'Duplicate/reserved header: {label}')
        result.append(label)
    return result

def bounded_rows(ctx, rows):
    result = []
    limit = ctx.PARAMS['max_total_rows'] + 20
    for row in rows:
        if len(result) >= limit:
            raise ValueError('Source rows exceed max_total_rows; split the source or review the limit')
        result.append(row)
    return result

def read_rows(ctx, item, payload):
    name = item['name'].lower()
    if name.endswith(('.geojson', '.json')):
        return ingestion_parsers.read_geojson(payload)
    if name.endswith('.csv'):
        rows = ingestion_parsers.bounded_rows(ctx, csv.reader(io.StringIO(payload.decode('utf-8-sig')), strict=True))
        sheet = None
    else:
        workbook = ctx.openpyxl.load_workbook(io.BytesIO(payload), read_only=True, data_only=True)
        try:
            sheet = ctx.SHEET_OVERRIDES.get(item['id'])
            if not sheet:
                candidates = []
                for ws in workbook.worksheets:
                    header = next(ws.iter_rows(values_only=True), ())
                    labels = {str(v).strip().lower() for v in header if v is not None}
                    long_name = re.sub('[^a-z]', '', ws.title.lower()) in {'longform', 'longdata', 'populationlong', 'graduateslong'}
                    year_header = bool(labels & {'year', 'fiscal_year', 'reference_year', 'academic_year'})
                    if long_name or year_header:
                        candidates.append(ws.title)
                if len(candidates) != 1:
                    raise ValueError(f"Select a tab in SHEET_OVERRIDES for {item['name']}; tabs={workbook.sheetnames}, candidates={candidates}")
                sheet = candidates[0]
            rows = ingestion_parsers.bounded_rows(ctx, workbook[sheet].iter_rows(values_only=True))
        finally:
            workbook.close()
    if not rows:
        raise ValueError(f"Empty source: {item['name']}")
    header_offset = 0
    if ingestion_routing.route(item['relative_path']) == 'completion_rate':
        candidates = [i for i, row in enumerate(rows[:20]) if {'indicator', 'geolocation', 'level of education', 'sex'}.issubset({str(v).strip().lower() for v in row if v is not None})]
        if len(candidates) != 1:
            raise ValueError('Completion rate: expected one PSA header in first 20 rows')
        header_offset = candidates[0]
        rows = rows[header_offset:]
    headers = ingestion_parsers.clean_header(rows[0])
    records = []
    for number, row in enumerate(rows[1:], start=header_offset + 2):
        if not any((value is not None and str(value) != '' for value in row)):
            continue
        values = tuple((None if value is None else str(value) for value in row))
        rescued = None
        if len(values) != len(headers):
            rescued = json.dumps({'reason': 'column_count_mismatch', 'source_file': item['relative_path'], 'source_row': number, 'expected_columns': len(headers), 'actual_columns': len(values), 'headers': headers, 'original_values': values}, ensure_ascii=False)
            values = (None,) * len(headers)
        records.append(values + (rescued,))
    if not records:
        raise ValueError(f"Source has no data rows: {item['name']}")
    return (headers + ['_rescued_data'], records, sheet, dict(zip(headers, map(str, rows[0]))))
