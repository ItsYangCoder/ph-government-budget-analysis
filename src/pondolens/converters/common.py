"""Shared typed values, source row readers, and reconciliation controls."""

from decimal import Decimal, InvalidOperation
import hashlib
import json
import re

from pondolens.ingestion import excel_records

SCALES = {"PHP": Decimal(1), "thousand_PHP": Decimal(1000),
          "million_PHP": Decimal(1000000)}


def clean(value):
    return " ".join(str(value or "").split())


def number(value):
    if value is None or value == "":
        return None, "missing"
    if isinstance(value, bool):
        return None, "invalid_numeric"
    text = str(value).strip()
    if text in {"-", "–", "—"}:
        return None, "source_dash"
    if text.startswith("#"):
        return None, "source_excel_error"
    # Only accept valid grouping; never silently delete arbitrary characters.
    if not re.fullmatch(r"[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d+)?(?:[eE][+-]?\d+)?", text):
        return None, "invalid_numeric"
    try:
        result = Decimal(text.replace(",", ""))
    except InvalidOperation:
        return None, "invalid_numeric"
    return (result, "ok") if result.is_finite() else (None, "invalid_numeric")


def effective(cell):
    return cell.get("cached_value") if cell.get("excel_type") == "f" else cell.get("original_value")


def value(cells, column):
    return effective(cells.get(column, {}))


def rows_from_records(records):
    current = None
    cells = {}
    last = None
    for record in records:
        if record["kind"] != "cell":
            continue
        position = (record["sheet"], record["row"], record["column"])
        if last and position[0] == last[0] and position[1:] <= last[1:]:
            raise ValueError("Duplicate or unordered source cell")
        last = position
        row_key = position[:2]
        if current is not None and row_key != current:
            yield current[0], current[1], cells
            cells = {}
        current = row_key
        cells[record["column"]] = record
    if current is not None:
        yield current[0], current[1], cells


def excel_rows(path):
    yield from rows_from_records(excel_records(path))


def record(dataset, sheet, row, column, cell, *, unit, key, eligible=True, **dimensions):
    raw = effective(cell)
    amount, status = number(raw)
    if cell.get("missing_formula_cache"):
        status = "missing_formula_cache"
    key_text = json.dumps([dataset, *key], ensure_ascii=False, separators=(",", ":"))
    result = dict(dataset=dataset, record_key=hashlib.sha256(key_text.encode()).hexdigest(),
                  source_table=sheet, source_row=row, source_column=column,
                  raw_value=json.dumps(raw, ensure_ascii=False),
                  original_formula=cell.get("original_value") if cell.get("excel_type") == "f" else "",
                  unit=unit, value="" if amount is None else str(amount),
                  value_php=str(amount * SCALES[unit]) if amount is not None and unit in SCALES else "",
                  value_status=status, analytical_eligible=eligible,
                  **dimensions)
    return result


class Controls:
    def __init__(self):
        self.checks = []
        self.notes = []
        self.blockers = []

    def reconcile(self, name, expected, actual, tolerance="0.001"):
        passed = expected is not None and actual is not None and abs(expected - actual) <= Decimal(tolerance)
        self.checks.append(dict(check=name, expected=str(expected), actual=str(actual),
                                tolerance=str(tolerance), passed=passed))

    def require(self, condition, reason):
        if not condition:
            self.blockers.append(reason)


def numeric_cell(cells, column):
    return number(value(cells, column))[0]


def year_from_title(cells):
    match = re.search(r"\bFY\s*(20\d{2})\b", clean(value(cells, 1)))
    return int(match[1]) if match else None
