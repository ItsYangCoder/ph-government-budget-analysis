"""Hashing, canonical representation and configuration checks."""
import hashlib
import json
import math
import re
from datetime import date, datetime, timezone
from pathlib import Path


class ExtractionError(ValueError):
    """A source or its extraction configuration failed validation."""


def utcnow():
    return datetime.now(timezone.utc).isoformat()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def file_hash(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def scalar(value):
    if isinstance(value, (datetime, date)):
        return {"type": type(value).__name__, "value": value.isoformat()}
    if isinstance(value, float) and not math.isfinite(value):
        return {"type": "nonfinite", "value": repr(value)}
    return value


def raw_cell(cell, cached=None):
    return {"value": scalar(cell.value), "excel_type": cell.data_type,
            "number_format": cell.number_format,
            "cached_value": scalar(cached.value) if cached is not None and cell.data_type == "f" else None}


def parse_number(cell, cached=None):
    value = cell.value
    flags = []
    if cell.data_type == "f":
        flags.append("formula_cached_value_not_recalculated")
        value = cached.value if cached is not None else None
    if cell.data_type == "e" or (cached is not None and cell.data_type == "f" and cached.data_type == "e"):
        return None, flags + ["source_error"]
    if value is None:
        return None, flags + ["source_blank"]
    if isinstance(value, str) and value.strip() in {"-", "–", "—"}:
        return None, flags + ["source_dash_undefined"]
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
        return float(value), flags
    return None, flags + ["source_nonnumeric"]


def validate_config(config):
    ids = []
    for src in config.get("sources", []):
        if not re.fullmatch(r"[A-Za-z0-9_-]+", src.get("source_id", "")):
            raise ExtractionError("source_id must be a safe identifier")
        ids.append(src["source_id"])
        if not src.get("glob") or not src.get("adapter"):
            raise ExtractionError("Every source needs glob and adapter")
        for table in src.get('tables', []):
            if not re.fullmatch(r'[A-Za-z0-9_-]+', table.get('table_id', '')):
                raise ExtractionError('table_id must be a safe identifier')
    if not ids or len(ids) != len(set(ids)):
        raise ExtractionError("Source IDs must be present and unique")
    return config
