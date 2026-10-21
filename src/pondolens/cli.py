"""CLI entry point; uses defaults when no arguments are supplied."""
from pondolens.common.dependencies import ensure_dependencies
from pondolens.common.config import parameters
from pondolens.ingestion.pipeline import run

def main():
    ensure_dependencies()
    run(parameters())
if __name__ == '__main__':
    main()
