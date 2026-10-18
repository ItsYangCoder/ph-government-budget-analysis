"""Validate Python syntax and notebook structure without running the pipeline."""

import ast
from pathlib import Path

import nbformat


SCAN_FOLDERS = (
    "databricks",
    "scripts",
    "src",
    "platform",
    "orchestration",
    "profiling",
    "tests",
    "data_quality",
)

try:
    ROOT = Path(__file__).resolve().parents[1]
except NameError:
    # __file__ is undefined when run as a notebook/REPL command; fall back
    # to the working directory (going up one level if inside a scan folder).
    ROOT = Path.cwd()
    if ROOT.name in SCAN_FOLDERS:
        ROOT = ROOT.parent

SKIP_FOLDERS = {
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    ".ipynb_checkpoints",
    "node_modules",
    "site-packages",
}

NON_PYTHON_MAGICS = {
    "%sql",
    "%scala",
    "%r",
    "%sh",
    "%md",
    "%pip",
    "%run",
    "%%sql",
    "%%sh",
    "%%bash",
    "%%scala",
    "%%r",
    "%%html",
    "%%javascript",
}

errors = []
python_files_checked = 0
notebooks_checked = 0
python_cells_checked = 0


def check_python(source, label):
    """Parse Python source without executing it."""
    try:
        ast.parse(source, filename=label)
    except (SyntaxError, ValueError) as exc:
        line = getattr(exc, "lineno", None)
        message = getattr(exc, "msg", str(exc))
        location = f" at line {line}" if line else ""
        errors.append(f"{label}: {message}{location}")


def discover_files():
    """Find supported files inside existing project folders."""
    paths = set()

    for folder in SCAN_FOLDERS:
        directory = ROOT / folder

        if not directory.is_dir():
            continue

        for path in directory.rglob("*"):
            relative = path.relative_to(ROOT)

            if any(part in SKIP_FOLDERS for part in relative.parts):
                continue

            if path.is_file() and path.suffix in {".py", ".ipynb"}:
                paths.add(path)

    return sorted(paths)


def check_notebook(path, label):
    """Validate notebook structure and supported Python cells."""
    global notebooks_checked, python_cells_checked

    try:
        notebook = nbformat.read(path, as_version=4)
        nbformat.validate(notebook)
    except Exception as exc:
        errors.append(f"{label}: invalid notebook: {exc}")
        return

    notebooks_checked += 1

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

        if command in NON_PYTHON_MAGICS:
            continue

        if command in {"%python", "%%python"}:
            source = "\n".join(lines[1:])
        elif default_language not in {"python", "python3"}:
            continue

        check_python(source, f"{label}, cell {index}")
        python_cells_checked += 1


def main():
    global python_files_checked

    paths = discover_files()

    if not paths:
        raise SystemExit(
            "No Python files or notebooks found. Check SCAN_FOLDERS."
        )

    for path in paths:
        label = str(path.relative_to(ROOT))

        if path.suffix == ".ipynb":
            check_notebook(path, label)
            continue

        try:
            source = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as exc:
            errors.append(f"{label}: cannot read file: {exc}")
            continue

        check_python(source, label)
        python_files_checked += 1

    if errors:
        raise SystemExit(
            f"Checks failed ({len(errors)} issues):\n"
            + "\n".join(errors)
        )

    print(
        f"Passed: {python_files_checked} Python files, "
        f"{notebooks_checked} notebooks, "
        f"{python_cells_checked} Python notebook cells checked."
    )


if __name__ == "__main__":
    main()