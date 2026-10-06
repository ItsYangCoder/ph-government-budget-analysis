"""Tiny synthetic OOXML fixtures created with the standard library, no real data."""
import copy
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZipFile

import pytest


def write_xlsx(path, cells, sheet='Capita', merges=()):
    rows = {}
    for address, value in cells.items():
        row = int(''.join(c for c in address if c.isdigit()))
        if value is None:
            cell = f'<c r="{address}"/>'
        elif isinstance(value, (int, float)):
            cell = f'<c r="{address}"><v>{value}</v></c>'
        elif value.startswith('#'):
            cell = f'<c r="{address}" t="e"><v>{escape(value)}</v></c>'
        else:
            cell = f'<c r="{address}" t="inlineStr"><is><t xml:space="preserve">{escape(value)}</t></is></c>'
        rows.setdefault(row, []).append(cell)
    with ZipFile(path, 'w') as z:
        z.writestr('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
        z.writestr('_rels/.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr('xl/workbook.xml', f'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="{sheet}" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        merge_xml = '<mergeCells>' + ''.join(f'<mergeCell ref="{r}"/>' for r in merges) + '</mergeCells>' if merges else ''
        z.writestr('xl/worksheets/sheet1.xml', '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' + ''.join(f'<row r="{r}">{"".join(cs)}</row>' for r, cs in sorted(rows.items())) + '</sheetData>' + merge_xml + '</worksheet>')


@pytest.fixture
def source(tmp_path):
    incoming = tmp_path / 'incoming'
    incoming.mkdir()
    cells = {'A1': 'Test per-capita data', 'A2': 'At Current Prices', 'A3': 'release date',
             'D4': 2024, 'E4': 2025, 'A5': 'AA', 'B5': 'Region A', 'D5': 12.5, 'E5': 13.0,
             'B6': 'Philippines', 'D6': 12.5, 'E6': 13.0}
    path = incoming / 'source.xlsx'
    write_xlsx(path, cells)
    src = {'source_id': 'test_grdp', 'glob': '*.xlsx', 'adapter': 'per_capita_grdp',
           'sheet': 'Capita', 'headers': [{'cell': 'A1', 'regex': '^Test per-capita data$'}],
           'name_col': 2, 'abbreviation_col': 1,
           'years': [{'year': 2024, 'col': 4}, {'year': 2025, 'col': 5}],
           'tables': [{'table_id': 'current', 'basis_cell': 'A2', 'price_basis_raw': 'At Current Prices',
                       'year_row': 4, 'first_region': 5, 'last_region': 5, 'national_row': 6,
                       'publication_cell': 'A3'}],
           'region_labels': ['Region A'], 'unit': 'PHP_per_person', 'expected_record_count': 4,
           'controls': [{'cell': 'D5', 'expected': 12.5}]}
    return {'config': {'sources': [src]}, 'input': incoming, 'output': tmp_path / 'runtime',
            'path': path, 'cells': cells}
