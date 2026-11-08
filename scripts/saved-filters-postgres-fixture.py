"""Opt-in saved filters acceptance using the existing bounded owned repository lifecycle."""
import argparse
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location('saved_filters_repository_lifecycle', Path(__file__).with_name('category-postgres-fixture.py'))
repository = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(repository)


def verify_recovery(runtime, name, database, identity, folder):
    """Load the fixed recovery helper only after explicit opt-in."""
    spec = importlib.util.spec_from_file_location('saved_filters_database_recovery', Path(__file__).with_name('saved-filters-database-recovery.py'))
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    helper.verify(runtime, name, database, identity, folder, repository.client)


def main():
    """Run the fixed saved filters profile once; never pull, retry or touch regular data."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    parser.add_argument('--verify-recovery', action='store_true')
    parser.add_argument('--image', default='')
    args = parser.parse_args()
    try:
        if args.verify_recovery and not Path(__file__).with_name('saved-filters-database-recovery.py').is_file():
            raise repository.client.Refusal('Recovery helper missing')
        repository.execute(Path(__file__).resolve().parent.parent, args,
                           repository.client.Runtime(seconds=120), profile='saved-filters',
                           verification=verify_recovery if args.verify_recovery else None)
    except (repository.client.Refusal, OSError, ValueError):
        print('Saved filters fixture failed/refused; no retry, inspect retained evidence.')
        return 1
    print('Saved filters repository assertions completed; owned container stopped.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
