import ast
from pathlib import Path

import nbformat

ROOT = Path(__file__).resolve().parents[1]
errors = []
checked = 0


def check_python(source, label):
    try:
        ast.parse(source, filename=label)
    except SyntaxError as exc:
        errors.append(f"{label}: {exc.msg} at line {exc.lineno}")


# Check Python syntax without running the ingestion.
for folder in ("databricks", "scripts"):
    for path in (ROOT / folder).rglob("*.py"):
        label = str(path.relative_to(ROOT))
        check_python(path.read_text(encoding="utf-8"), label)
        checked += 1


# Validate notebook structure and Python code cells.
for path in (ROOT / "databricks").rglob("*.ipynb"):
    label = str(path.relative_to(ROOT))

    try:
        notebook = nbformat.read(path, as_version=4)
        nbformat.validate(notebook)
    except Exception as exc:
        errors.append(f"{label}: invalid notebook: {exc}")
        continue

    for index, cell in enumerate(notebook.cells, start=1):
        if cell.cell_type != "code" or not cell.source.strip():
            continue

        source = cell.source.lstrip()
        first_line = source.splitlines()[0].strip()

        # Skip cells written in other notebook languages.
        if first_line in ("%sql", "%scala", "%r", "%sh", "%md"):
            continue

        if first_line == "%python":
            source = "\n".join(source.splitlines()[1:])

        check_python(source, f"{label}, cell {index}")

    checked += 1


if errors:
    raise SystemExit("Checks failed:\n" + "\n".join(errors))

print(f"Passed: {checked} Python files and notebooks checked.")