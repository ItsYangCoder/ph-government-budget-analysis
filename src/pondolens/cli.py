"""CLI entry point; exits nonzero for failed or missing configured sources."""
import argparse
import json
from pathlib import Path

from .pipeline import run_pipeline


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', required=True)
    p.add_argument('--input-root', required=True)
    p.add_argument('--output-root', default='runtime')
    p.add_argument('--batch-id', required=True)
    args = p.parse_args()
    config = json.loads(Path(args.config).read_text())
    result = run_pipeline(config, args.input_root, args.output_root, args.batch_id)
    print(json.dumps(result, indent=2))
    return 1 if result['counts']['FAILED'] or result['counts']['MISSING'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
