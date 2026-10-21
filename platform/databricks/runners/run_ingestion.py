"""Databricks entry point. Run this file from the checked-out repository."""
import sys
from pathlib import Path

# Support script execution and execution pasted into a repo notebook.
if "__file__" in globals():
    repo_root = Path(__file__).resolve().parents[3]
else:
    current = Path.cwd().resolve()
    repo_root = next((p for p in (current, *current.parents)
                      if (p / "src" / "pondolens").is_dir()), None)
    if repo_root is None:
        raise RuntimeError("Open this runner inside the repository, or install the package first.")
sys.path.insert(0, str(repo_root / "src"))

from pondolens.common.dependencies import ensure_dependencies
from pondolens.common.config import DEFAULTS, DATASET_NAMES, WIDGET_NAMES, parameters
from pondolens.ingestion.pipeline import run

def widget_parameters(native=None):
    """Use the native Databricks widget API without a separate runner notebook."""
    if native is None:
        import builtins
        native = getattr(builtins, 'dbutils', None)
    if native is None:
        try:
            from databricks.sdk.runtime import dbutils as native
        except (ImportError, RuntimeError) as exc:
            raise RuntimeError('Native dbutils is unavailable for interactive widgets. Use explicit CLI parameters for a Job run.') from exc
    widgets = getattr(native, 'widgets', None)
    if widgets is None:
        raise RuntimeError('This dbutils instance has no native widgets API. No ingestion was started.')
    choices = {'dataset': ['all'] + DATASET_NAMES, 'dry_run': ['true', 'false']}
    try:
        for name in DEFAULTS.keys() - set(WIDGET_NAMES):
            try:
                widgets.get(name)
            except Exception:
                continue
            widgets.remove(name)
        for name in WIDGET_NAMES:
            if name in choices:
                widgets.dropdown(name, DEFAULTS[name], choices[name])
            else:
                widgets.text(name, DEFAULTS[name])
        result = dict(DEFAULTS)
        result.update({name: widgets.get(name).strip() for name in WIDGET_NAMES})
    except (AttributeError, NotImplementedError) as exc:
        raise RuntimeError('Native widget creation is unsupported in this execution context. No ingestion was started; use the original interactive context or explicit Job CLI parameters.') from exc
    print('Parameters: Databricks widgets initialized.', flush=True)
    return result

if __name__ == "__main__":
    ensure_dependencies()
    native = globals().get("dbutils")
    params = parameters(widget_provider=lambda: widget_parameters(native))
    run(params, spark=globals().get("spark"), dbutils=native)
