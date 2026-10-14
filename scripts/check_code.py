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

    # Databricks SQL-default cells do not need an explicit %sql marker.
    databricks_metadata = notebook.metadata.get(
        "application/vnd.databricks.v1+notebook", {}
    )
    default_language = str(
        databricks_metadata.get("language")
        or notebook.metadata.get("language_info", {}).get("name")
        or notebook.metadata.get("kernelspec", {}).get("language")
        or "python"
    ).lower()

    for index, cell in enumerate(notebook.cells, start=1):
        if cell.cell_type != "code" or not cell.source.strip():
            continue

        source = cell.source.lstrip()
        lines = source.splitlines()
        command = lines[0].strip().split(maxsplit=1)[0]

        # Skip cells that use another language or install packages.
        if command in (
             "%sql", "%scala", "%r", "%sh", "%md", "%pip",
             "%%sql", "%%sh", "%%bash",
             "%%scala", "%%r", "%%html", "%%javascript",
        ):
            continue

        # Explicit cell language overrides the notebook default.
        if command in ("%python", "%%python"):
            source = "\n".join(lines[1:])
        elif default_language not in ("python", "python3"):
            continue

        check_python(source, f"{label}, cell {index}")

    checked += 1


if errors:
    raise SystemExit("Checks failed:\n" + "\n".join(errors))

print(f"Passed: {checked} Python files and notebooks checked.")