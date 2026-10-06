"""Text-backed PDF adapters: preserve tokens and validate explicit layouts."""
import re
import pdfplumber

from .adapters import Extraction
from .common import ExtractionError, canonical


def numeric_token(raw):
    compact = re.sub(r'\s+', '', raw)
    if compact in {'-', '–', '—'}:
        return None, ['source_dash_undefined']
    if not compact:
        raise ExtractionError('Empty PDF numeric cell; layout may have shifted')
    if not re.fullmatch(r'-?\d[\d,]*(?:\.\d+)?', compact):
        raise ExtractionError(f'Unrecognized numeric PDF token: {raw!r}')
    return float(compact.replace(',', '')), []


def pdf_record(result, table, page, row, column, raw, dims, flags, bbox=None):
    number, parsing = numeric_token(raw)
    result.records.append({'table_id': table, 'source_sheet': None, 'source_page': page,
        'source_row': row, 'source_record_locator': f'page:{page}/row:{row}/column:{column}',
        'raw_value_json': canonical({'value': raw, 'representation': 'pdf_text_tokens', 'bbox': bbox}),
        'parsed_numeric': number, 'dimensions_json': canonical(dims),
        'quality_flags': sorted(set(flags + parsing))})


def sector_text(text, config, result):
    token = r'(?:-?\d[\d,]*(?:\.\d+)?|[-–—])'
    pattern = re.compile(r'^(.+?)\s+(' + token + r')\s+(' + token + r')\s+(' + token +
                         r')\s+(' + token + r')\s+(' + token + r')\s+(' + token + r')\s*$')
    data = []
    for line in text.splitlines():
        match = pattern.fullmatch(line)
        if match:
            data.append((line, match.groups()))
    if len(data) != config['expected_rows']:
        raise ExtractionError(f"Sector row count changed: {len(data)} vs {config['expected_rows']}")
    if [g[0] for _, g in data] != config['row_labels']:
        raise ExtractionError('Sector labels/hierarchy changed')
    parent = None
    for i, (line, groups) in enumerate(data, 1):
        label = groups[0]
        if label in config['parent_labels']:
            parent = label
        kind = 'grand_total' if label == 'GRAND TOTAL' else 'parent' if label in config['parent_labels'] else 'detail'
        for col, token in enumerate(groups[1:]):
            period = config['periods'][col % 3]
            dims = {'label_raw': label, 'parent_label': parent if kind == 'detail' else None,
                    'row_kind': kind, 'year': period['year'], 'reporting_status': period['status'],
                    'measure': 'cash_based_expenditure' if col < 3 else 'percent_distribution',
                    'unit': config['unit'] if col < 3 else 'percent',
                    'measurement_basis': 'CASH-BASED', 'raw_line': line}
            pdf_record(result, 'sector_amounts' if col < 3 else 'sector_shares', 1, i, col + 1,
                       token, dims, config.get('quality_flags', []))
    grand = data[-1][1]
    actual = numeric_token(grand[1])[0]
    if actual != config['grand_total']:
        raise ExtractionError('Sector published actual grand total mismatch')
    for col in range(3):
        top = sum(numeric_token(g[col + 1])[0] for _, g in data if g[0] in config['parent_labels'])
        total = numeric_token(grand[col + 1])[0]
        if abs(top - total) > config.get('tolerance', 2):
            raise ExtractionError('Sector parent totals do not reconcile to grand total')
    result.checks.append({'name': 'sector_controls_and_hierarchy', 'passed': True, 'rows': len(data)})


def regional_grid(words, page_cfg):
    """Group numeric rows, retain within-cell tokens, and associate nearby labels."""
    edges = page_cfg['column_edges']
    first = [w for w in words if w['text'] == 'DEPARTMENTS']
    if len(first) != 1:
        raise ExtractionError('Regional DEPARTMENTS marker missing or ambiguous')
    lower = first[0]['top'] - 1
    numeric_words = [w for w in words if w['x0'] >= edges[0] and w['x1'] <= edges[-1]
                     and w['top'] >= lower
                     and re.fullmatch(r'[\d,\.\-–—]+', w['text'])]
    groups = []
    for word in sorted(numeric_words, key=lambda w: (w['top'], w['x0'])):
        if not groups or abs(groups[-1][0]['top'] - word['top']) > 2:
            groups.append([word])
        else:
            groups[-1].append(word)
    # Stop at GRAND TOTAL rather than accepting footer numeric tokens.
    grand = [w for w in words if w['text'] == 'GRAND' and w['top'] >= lower]
    if len(grand) != 1:
        raise ExtractionError('Regional GRAND TOTAL marker missing/ambiguous')
    groups = [g for g in groups if g[0]['top'] <= grand[0]['top'] + 2]
    result = []
    for i, group in enumerate(groups):
        y = group[0]['top']
        prev = groups[i-1][0]['top'] if i else y - 10
        nxt = groups[i+1][0]['top'] if i+1 < len(groups) else y + 10
        label_words = [w for w in words if w['x1'] < edges[0] and
                       (prev + y) / 2 <= w['top'] < (y + nxt) / 2]
        label = ' '.join(w['text'] for w in sorted(label_words, key=lambda w: (round(w['top'], 1), w['x0'])))
        cells = []
        for left, right in zip(edges, edges[1:]):
            tokens = sorted([w for w in group if left <= (w['x0']+w['x1'])/2 < right], key=lambda w: w['x0'])
            raw = ' '.join(w['text'] for w in tokens)
            numeric_token(raw)  # Reject incomplete cells; never shift following values left.
            cells.append((raw, [left, y, right, max(w['bottom'] for w in group)]))
        result.append((label, cells))
    return result


def validate_continuation(first, second, expected_rows):
    if len(first) != expected_rows or len(second) != expected_rows:
        raise ExtractionError('Regional continuation row counts differ')
    def key(label):
        return re.sub(r'[^A-Za-z0-9]', '', label).lower()
    if any(not key(a[0]) or key(a[0]) != key(b[0]) for a, b in zip(first, second)):
        raise ExtractionError('Regional continuation labels do not match; row order alone is insufficient')


def extract_pdf(path, config):
    result = Extraction()
    with pdfplumber.open(path) as pdf:
        if len(pdf.pages) != config['expected_pages']:
            raise ExtractionError('PDF page count changed')
        pages = []
        for page in pdf.pages:
            text = page.extract_text(x_tolerance=2, y_tolerance=2) or ''
            words = page.extract_words(x_tolerance=1, y_tolerance=2)
            if not text.strip() or not words:
                raise ExtractionError('No usable PDF text; OCR review required')
            pages.append({'page': page.page_number, 'width': page.width, 'height': page.height,
                          'text': text, 'words': words})
        result.metadata = {'pages': pages, 'representation': 'PDF text layer; original bytes retained'}
        for expected in config.get('headers', []):
            if not re.search(expected['regex'], pages[expected['page']-1]['text']):
                raise ExtractionError(f"PDF header mismatch on page {expected['page']}")
        if config['adapter'] == 'pdf_sector':
            sector_text(pages[0]['text'], config, result)
        elif config['adapter'] == 'pdf_regional':
            grids = [regional_grid(pages[i]['words'], spec) for i, spec in enumerate(config['pages'])]
            validate_continuation(grids[0], grids[1], config['expected_rows'])
            if not grids[-1][-1][0].replace(' ', '').upper().startswith('GRANDTOTAL'):
                raise ExtractionError('Last regional row is not GRAND TOTAL')
            for i, (label, cells1) in enumerate(grids[0], 1):
                for page_num, cells, spec in [(1,cells1,config['pages'][0]),(2,grids[1][i-1][1],config['pages'][1])]:
                    for j, ((raw, bbox), column) in enumerate(zip(cells,spec['columns']),1):
                        dims = {'label_raw': label, 'column_raw': column, 'year': config['year'],
                                'reporting_status': config['reporting_status'], 'unit': config['unit'],
                                'row_kind': 'unclassified_source_row', 'geographic_coverage': 'source_defined'}
                        pdf_record(result, 'regional_cells',page_num,i,j,raw,dims,
                                   config.get('quality_flags', []),bbox)
            actual = numeric_token(grids[0][-1][1][0][0])[0]
            if actual != config['grand_total']:
                raise ExtractionError('Regional published grand total mismatch')
            all_grand = grids[0][-1][1][1:] + grids[1][-1][1]
            numbers = [numeric_token(c[0])[0] for c in all_grand]
            if any(v is None for v in numbers) or abs(sum(numbers)-actual) > config.get('tolerance',20):
                raise ExtractionError('Regional GRAND TOTAL geographic columns do not reconcile')
            result.checks.append({'name':'regional_continuation_and_grand_total','passed':True})
        else:
            raise ExtractionError(f"Unsupported PDF adapter: {config['adapter']}")
    if len(result.records) != config['expected_record_count']:
        raise ExtractionError('PDF extracted record count mismatch')
    return result
