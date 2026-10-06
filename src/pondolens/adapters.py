"""Verified layout adapters. Interpretation remains source-specific."""
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import datetime
import re

import openpyxl
from openpyxl.utils import get_column_letter

from .common import ExtractionError, canonical, raw_cell, parse_number, scalar


@dataclass
class Extraction:
    records: list = field(default_factory=list)
    metadata: dict = field(default_factory=dict)
    checks: list = field(default_factory=list)


@contextmanager
def workbooks(path, config):
    raw = openpyxl.load_workbook(path, data_only=False, keep_links=False)
    cached = openpyxl.load_workbook(path, data_only=True, keep_links=False)
    try:
        sheet = config["sheet"]
        if sheet not in raw.sheetnames:
            raise ExtractionError(f"Required sheet missing: {sheet}")
        s = raw[sheet]
        for check in config.get("headers", []):
            value = s[check["cell"]].value
            if value is None or not re.search(check["regex"], str(value)):
                raise ExtractionError(f"Header mismatch at {sheet}!{check['cell']}: {value!r}")
        yield raw, cached, s, cached[sheet]
    finally:
        raw.close()
        cached.close()


def metadata(raw, sheet):
    # Retain all populated cells, including notes, headers, annotations and other tables.
    # Blank selected measure cells are retained in the records themselves.
    return {"sheets": raw.sheetnames, "sheet": sheet.title,
            "sheet_state": sheet.sheet_state,
            "merged_ranges": [str(r) for r in sheet.merged_cells.ranges],
            "cells": [{"cell": c.coordinate, **raw_cell(c)} for row in sheet for c in row if c.value is not None]}


def add_measure(result, sheet, cache, table, row, col, dimensions, flags):
    cell = sheet.cell(row, col)
    number, parse_flags = parse_number(cell, cache.cell(row, col))
    result.records.append({
        "table_id": table, "source_sheet": sheet.title, "source_page": None,
        "source_row": row, "source_record_locator": f"{sheet.title}!{cell.coordinate}",
        "raw_value_json": canonical(raw_cell(cell, cache.cell(row, col))),
        "parsed_numeric": number, "dimensions_json": canonical(dimensions),
        "quality_flags": sorted(set(flags + parse_flags)),
    })


def controls(result, config):
    by_location = {r["source_record_locator"]: r for r in result.records}
    for control in config.get("controls", []):
        loc = f"{config['sheet']}!{control['cell']}"
        row = by_location.get(loc)
        actual = row["parsed_numeric"] if row else None
        expected, tolerance = control["expected"], control.get("tolerance", 0)
        passed = actual is not None and abs(actual - expected) <= tolerance
        check = {"name": f"published_control:{loc}", "actual": actual,
                 "expected": expected, "tolerance": tolerance, "passed": passed,
                 "scope": control.get("scope"), "unit": control.get("unit")}
        result.checks.append(check)
        if not passed:
            raise ExtractionError(f"Published control mismatch: {canonical(check)}")
    expected_count = config.get("expected_record_count")
    if expected_count is not None and len(result.records) != expected_count:
        raise ExtractionError(f"Expected {expected_count} records, extracted {len(result.records)}")
    result.checks.append({"name": "record_count", "actual": len(result.records), "passed": True})
    locs = [r["source_record_locator"] + ':' + r["table_id"] for r in result.records]
    if len(locs) != len(set(locs)):
        raise ExtractionError("Extraction generated duplicate table/source locations")


def population(path, config):
    result = Extraction()
    with workbooks(path, config) as (raw, cached, sheet, cache):
        result.metadata = metadata(raw, sheet)
        b = config["blocks"]
        years = config["years"]
        if len({y['year'] for y in years}) != len(years):
            raise ExtractionError("Duplicate population year groups")
        for y in years:
            value = sheet.cell(config["date_header_row"], y["start_col"]).value
            text = value.strftime("%d %B %Y") if isinstance(value, datetime) else str(value)
            if not re.fullmatch(y["date_regex"], text):
                raise ExtractionError(f"Population date mismatch for {y['year']}: {value!r}")
            for offset, sex in enumerate(config["sexes"]):
                if sheet.cell(config["sex_header_row"], y["start_col"] + offset).value != sex:
                    raise ExtractionError("Population sex header mismatch")
        # Detect inserted/removed geographic blocks before applying the configured stride.
        actual_totals = [r for r in range(b["first_heading"], b["data_end"] + 1)
                         if sheet.cell(r, config["label_col"]).value == "Total"]
        expected_totals = [b["first_heading"] + i * b["stride"] + 1 for i in range(b["count"])]
        if actual_totals != expected_totals:
            raise ExtractionError("Population block layout changed")
        seen = []
        for i in range(b["count"]):
            heading = b["first_heading"] + i * b["stride"]
            region = sheet.cell(heading, config["label_col"]).value
            if not isinstance(region, str) or not region.strip():
                raise ExtractionError(f"Missing geographic heading at row {heading}")
            seen.append(region)
            panel_col = config.get('panel_label_col', config['label_col'])
            if sheet.cell(heading, panel_col).value != region:
                raise ExtractionError('Population panel geographic label mismatch')
            for j, age in enumerate(config["ages"]):
                row = heading + 1 + j
                if sheet.cell(row, config["label_col"]).value != age:
                    raise ExtractionError(f"Population age layout changed at row {row}")
                if sheet.cell(row, panel_col).value != age:
                    raise ExtractionError('Population panel age label mismatch')
                for y in years:
                    # Check labels on the horizontal panel from which measures are read.
                    for offset, sex in enumerate(config["sexes"]):
                        dims = {"region_raw": region, "age_group_raw": age, "sex_raw": sex,
                                "year": y["year"], "reference_date_raw": scalar(sheet.cell(config["date_header_row"], y["start_col"]).value),
                                "unit": config["unit"], "measure": "projected_midyear_population",
                                "row_kind": "national" if i == 0 else "regional", "price_basis": None}
                        add_measure(result, sheet, cache, "population", row, y["start_col"] + offset,
                                    dims, config.get("quality_flags", []))
        if len(set(seen)) != len(seen) or seen != config["region_labels"]:
            raise ExtractionError("Population geographic labels changed; review new layout")
        for y in years:
            national, _ = parse_number(sheet.cell(expected_totals[0], y['start_col']))
            values = [parse_number(sheet.cell(r, y['start_col']))[0] for r in expected_totals[1:]]
            delta = sum(values) - national if national is not None and all(v is not None for v in values) else None
            result.checks.append({"name": f"regional_total_diagnostic:{y['year']}",
                                  "difference": delta, "blocking": False,
                                  "note": "Source discrepancy retained; no forced balancing."})
            if delta != 0:
                for record in result.records:
                    if f'"year":{y["year"]}' in record['dimensions_json']:
                        record['quality_flags'].append('regional_total_discrepancy')
        controls(result, config)
    return result


def per_capita(path, config):
    result = Extraction()
    with workbooks(path, config) as (raw, cached, sheet, cache):
        result.metadata = metadata(raw, sheet)
        for table in config["tables"]:
            if sheet[table['basis_cell']].value != table['price_basis_raw']:
                raise ExtractionError(f"Price-basis mismatch: {table['table_id']}")
            rows = list(range(table['first_region'], table['last_region'] + 1)) + [table['national_row']]
            names = [sheet.cell(r, config['name_col']).value for r in rows]
            if names != config['region_labels'] + ['Philippines']:
                raise ExtractionError(f"GRDP geographic layout changed: {table['table_id']}")
            for y in config['years']:
                if sheet.cell(table['year_row'], y['col']).value != y['year']:
                    raise ExtractionError("GRDP year header mismatch")
                for row in rows:
                    abbrev = sheet.cell(row, config['abbreviation_col']).value
                    dims = {"region_raw": sheet.cell(row, config['name_col']).value,
                            "region_abbreviation_raw": abbrev, "year": y['year'],
                            "unit": config['unit'], "measure": "per_capita_grdp",
                            "price_basis_raw": table['price_basis_raw'],
                            "publication_date_raw": sheet[table['publication_cell']].value,
                            "row_kind": "national" if row == table['national_row'] else "regional"}
                    flags = config.get('quality_flags', []) + (['source_abbreviation_blank'] if abbrev is None else [])
                    add_measure(result, sheet, cache, table['table_id'], row, y['col'], dims, flags)
        controls(result, config)
    return result


def excel_cells(path, config):
    """Agency extension: physical cells, with no guessed financial interpretation."""
    result = Extraction()
    with workbooks(path, config) as (raw, cached, sheet, cache):
        result.metadata = metadata(raw, sheet)
        for bounds in config['ranges']:
            for row in sheet[bounds]:
                for cell in row:
                    dims = {"column": get_column_letter(cell.column), "unit": config.get('unit'),
                            "source_reporting_period": config.get('reporting_period'),
                            "row_kind": "unclassified_raw_cell"}
                    add_measure(result, sheet, cache, 'raw_cells', cell.row, cell.column,
                                dims, config.get('quality_flags', []))
        controls(result, config)
    return result


def extract(path, config):
    adapters = {'population': population, 'per_capita_grdp': per_capita,
                'excel_cells': excel_cells}
    if config['adapter'].startswith('pdf_'):
        from .pdf_adapters import extract_pdf
        return extract_pdf(path, config)
    if config['adapter'] not in adapters:
        raise ExtractionError(f"Unsupported adapter: {config['adapter']}")
    return adapters[config['adapter']](path, config)
