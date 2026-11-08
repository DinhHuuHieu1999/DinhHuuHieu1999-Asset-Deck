"""Opt-in export-v3 acceptance using the existing bounded owned repository lifecycle."""
import argparse
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location('export-v3_repository_lifecycle', Path(__file__).with_name('category-postgres-fixture.py'))
repository = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(repository)


def main():
    """Run the fixed export-v3 profile once; never pull, retry or touch regular data."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    parser.add_argument('--image', default='')
    args = parser.parse_args()
    try:
        repository.execute(Path(__file__).resolve().parent.parent, args,
                           repository.client.Runtime(seconds=120), profile='export-v3')
    except (repository.client.Refusal, OSError, ValueError):
        print('Export v3 fixture failed/refused; no retry, inspect retained evidence.')
        return 1
    print('Export v3 repository assertions completed; owned container stopped.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
