"""Dependency bootstrap retained from the latest standalone script."""
import sys

def ensure_dependencies():
    """Install missing third-party packages in the current Python environment."""
    import importlib
    import importlib.util
    import subprocess
    required = {'openpyxl': 'openpyxl>=3.1,<4', 'googleapiclient': 'google-api-python-client>=2,<3', 'google.auth': 'google-auth>=2,<3', 'databricks.sdk': 'databricks-sdk>=0.30,<1'}
    missing = []
    for module, package in required.items():
        try:
            available = importlib.util.find_spec(module) is not None
        except ModuleNotFoundError:
            available = False
        if not available:
            missing.append(package)
    if not missing:
        return
    print('Installing missing dependencies: ' + ', '.join(missing), flush=True)
    try:
        subprocess.run([sys.executable, '-m', 'pip', 'install', '--disable-pip-version-check', *missing], check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError('Dependency installation failed. Configure openpyxl, google-api-python-client, google-auth and databricks-sdk in the Databricks compute/task environment, then rerun.') from exc
    importlib.invalidate_caches()
