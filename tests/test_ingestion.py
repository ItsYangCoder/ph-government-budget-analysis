from contextlib import closing
import sqlite3

import openpyxl
import pytest

from pondolens.ingestion import EXPECTED, digest, discover, excel_records, pdf_records, run


def make_pdf(path):
    text = b"BT /F1 12 Tf 20 150 Td (Particulars Total Region I) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(text)).encode() + b" >>\nstream\n" + text + b"\nendstream",
    ]
    data = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, obj in enumerate(objects, start=1):
        offsets.append(len(data))
        data.extend(f"{number} 0 obj\n".encode() + obj + b"\nendobj\n")
    start = len(data)
    data.extend(b"xref\n0 6\n0000000000 65535 f \n")
    for offset in offsets[1:]:
        data.extend(f"{offset:010d} 00000 n \n".encode())
    data.extend(f"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{start}\n%%EOF".encode())
    path.write_bytes(data)


@pytest.fixture
def sources(tmp_path):
    root = tmp_path / "raw"
    for folder, (extension, count) in EXPECTED.items():
        directory = root / folder
        directory.mkdir(parents=True)
        for number in range(count):
            path = directory / f"source{number}{extension}"
            if extension == ".pdf":
                make_pdf(path)
            else:
                book = openpyxl.Workbook()
                book.active.append(["Entity", "2024", "2025"])
                book.active.append(["Example", 0, 123.45])
                book.active["D2"] = "=B2+C2"
                book.save(path)
    return root


def test_rerun_preserves_inputs_and_has_no_duplicate_runs(sources, tmp_path):
    output = tmp_path / "outputs"
    before = {p: digest(p) for p in discover(sources)}
    assert all(r["status"] == "extracted" for r in run(sources, output))
    assert all(r["status"] == "skipped" for r in run(sources, output))
    assert before == {p: digest(p) for p in discover(sources)}
    with closing(sqlite3.connect(output / "audit.sqlite")) as db:
        assert db.execute("SELECT count(*) FROM runs").fetchone()[0] == 9


def test_changed_source_retains_previous_revision(sources, tmp_path):
    output = tmp_path / "outputs"
    run(sources, output)
    source = sources / "01_agency_actuals/source0.xlsx"
    old_hash = digest(source)
    book = openpyxl.load_workbook(source)
    book.active["B2"] = 999
    book.save(source)
    result = run(sources, output)
    assert sum(r["status"] == "extracted" for r in result) == 1
    assert (output / "originals" / f"{old_hash}.xlsx").exists()
    with closing(sqlite3.connect(output / "audit.sqlite")) as db:
        assert db.execute("SELECT count(*) FROM runs").fetchone()[0] == 10


def test_corrupt_output_is_rebuilt(sources, tmp_path):
    output = tmp_path / "outputs"
    first = run(sources, output)
    path = output / "structure" / f"{first[0]['run_id']}.jsonl"
    expected = path.read_bytes()
    path.write_text("corrupt")
    assert run(sources, output)[0]["status"] == "extracted"
    assert path.read_bytes() == expected


def test_formula_and_zero_are_preserved(sources):
    records = list(excel_records(sources / "01_agency_actuals/source0.xlsx"))
    zero = next(r for r in records if r.get("row") == 2 and r.get("column") == 2)
    formula = next(r for r in records if r.get("excel_type") == "f")
    assert zero["original_value"] == 0
    assert formula["original_value"] == "=B2+C2"
    assert formula["missing_formula_cache"] is True


def test_pdf_text_extraction(sources):
    records = list(pdf_records(sources / "04_regional_actuals/source0.pdf"))
    assert "Region I" in records[0]["text"]
    assert records[0]["requires_ocr_review"] is False


def test_failed_source_is_retried(sources, tmp_path, monkeypatch):
    import pondolens.ingestion as module
    original = module.excel_records
    def fail(path):
        raise ValueError("Injected extraction failure")
    monkeypatch.setattr(module, "excel_records", fail)
    assert sum(r["status"] == "failed" for r in run(sources, tmp_path / "outputs")) == 7
    monkeypatch.setattr(module, "excel_records", original)
    assert sum(r["status"] == "extracted" for r in run(sources, tmp_path / "outputs")) == 7


def test_missing_file_and_overlapping_output_fail(sources):
    with pytest.raises(ValueError, match="outside"):
        run(sources, sources / "output")
    next((sources / "04_regional_actuals").glob("*.pdf")).unlink()
    with pytest.raises(ValueError, match="expected 2"):
        discover(sources)
