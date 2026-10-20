"""Validate profiling packages offline; never execute their SQL."""
from pathlib import Path
import json
import re
from urllib.parse import unquote

import sqlglot
from sqlglot import exp

ROOT = Path(__file__).resolve().parents[1]


def validate_sql(source, label, seen_views=None):
    """Allow queries, DESCRIBE and unqualified temporary views only."""
    errors = []
    seen_views = seen_views if seen_views is not None else set()
    try:
        statements = sqlglot.parse(source, read='databricks', error_level=sqlglot.ErrorLevel.RAISE)
    except sqlglot.errors.ParseError as exc:
        return [f'{label}: SQL parse error: {exc}']
    if not any(s is not None for s in statements):
        errors.append(f'{label}: no SQL statements')
    for statement in statements:
        if statement is None or isinstance(statement, exp.Semicolon):
            continue
        if isinstance(statement, exp.Create):
            target = statement.this
            props = statement.args.get('properties')
            temporary = props and any(isinstance(p, exp.TemporaryProperty) for p in props.expressions)
            if (statement.args.get('kind') != 'VIEW' or not temporary
                    or not isinstance(target, exp.Table) or target.db or target.catalog
                    or not isinstance(statement.expression, exp.Query)):
                errors.append(f'{label}: only unqualified TEMP VIEW creation is allowed')
            else:
                key = target.name.lower()
                if key in seen_views:
                    errors.append(f'{label}: duplicate temporary view name: {key}')
                seen_views.add(key)
        elif not isinstance(statement, (exp.Query, exp.Describe)):
            errors.append(f'{label}: unsupported statement: {type(statement).__name__}')
        for node in statement.walk():
            if isinstance(node, (exp.Insert, exp.Update, exp.Delete, exp.Merge, exp.Drop, exp.Alter, exp.Command)):
                errors.append(f'{label}: prohibited SQL operation: {type(node).__name__}')
    return errors


def validate(root=ROOT):
    errors = []
    base = root / 'profiling'
    try:
        manifest = json.loads((base / 'manifest.json').read_text())
        datasets = manifest['datasets']
    except (OSError, ValueError, KeyError) as exc:
        return [f'manifest: {exc}']
    if manifest.get('version') != 1 or manifest.get('dialect') != 'databricks' or not datasets:
        errors.append('manifest: expected version 1, databricks dialect and nonempty datasets')
    registered = set()
    names = set()
    tables = set()
    seen_views = set()
    for item in datasets:
        name = item.get('dataset', '')
        table = item.get('table', '')
        relative = item.get('path', '')
        directory = base / relative
        if (not re.fullmatch(r'[a-z][a-z0-9_]*', name)
                or relative != f'bronze/{name}' or name in names
                or table in tables or not re.fullmatch(r'pondolens\.dev_bronze\.[a-z][a-z0-9_]*', table)
                or not item.get('owner') or item.get('scope') not in {'active', 'reference_only'}):
            errors.append(f'{name}: invalid or duplicate manifest entry')
            continue
        registered.add(relative)
        names.add(name)
        tables.add(table)
        for filename in ('profiling.sql', 'data_dictionary.md', 'findings.md'):
            file = directory / filename
            if not file.is_file() or not file.read_text().strip():
                errors.append(f'{file.relative_to(root)}: missing or empty')
        sql = directory / 'profiling.sql'
        if sql.is_file():
            source = sql.read_text()
            if f'-- Table: {table}' not in source:
                errors.append(f'{name}: missing registered table header')
            # A comment alone must not hide SQL accidentally pointing to another dataset.
            try:
                refs = {t.sql(dialect='databricks').lower() for s in sqlglot.parse(source, read='databricks')
                        if s is not None for t in s.find_all(exp.Table)}
                if table.lower() not in refs:
                    errors.append(f'{name}: SQL does not read registered table')
            except sqlglot.errors.ParseError:
                pass  # Detailed parse diagnostic below.
            errors.extend(validate_sql(source, str(sql.relative_to(root)), seen_views))
        findings = directory / 'findings.md'
        dictionary = directory / 'data_dictionary.md'
        for doc in (findings, dictionary):
            if doc.is_file() and table not in doc.read_text():
                errors.append(f'{doc.relative_to(root)}: registered table absent; check misfiled documentation')
    for directory in (base / 'bronze').iterdir():
        if directory.is_dir() and str(directory.relative_to(base)) not in registered:
            errors.append(f'{directory.relative_to(root)}: unregistered dataset directory')
    for file in base.rglob('*'):
        if not file.is_file():
            continue
        if any(part != part.strip() for part in file.relative_to(base).parts) or ' .' in file.name:
            errors.append(f'{file.relative_to(root)}: whitespace in canonical name')
        if file.suffix == '.ipynb':
            errors.append(f'{file.relative_to(root)}: notebook duplicates are not canonical profiling SQL')
        if file.suffix == '.md':
            for link in re.findall(r'\]\(([^)]+)\)', file.read_text()):
                if '://' in link or link.startswith(('#', 'mailto:')):
                    continue
                target = unquote(link.split('#', 1)[0])
                if target and not (file.parent / target).exists():
                    errors.append(f'{file.relative_to(root)}: broken link: {link}')
    overview = base / 'bronze/overview.sql'
    if not overview.is_file():
        errors.append('profiling/bronze/overview.sql: missing')
    else:
        errors.extend(validate_sql(overview.read_text(), 'overview.sql', seen_views))
    return errors


if __name__ == '__main__':
    failures = validate()
    if failures:
        raise SystemExit('\n'.join(failures))
    print('Profiling checks passed: registry, packages, links, SQL syntax and read-only statement policy.')
