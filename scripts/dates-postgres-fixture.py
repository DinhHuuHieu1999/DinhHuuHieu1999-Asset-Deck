"""Opt-in dates acceptance using the existing bounded owned repository lifecycle."""
import argparse
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location('dates_repository_lifecycle', Path(__file__).with_name('category-postgres-fixture.py'))
repository = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(repository)


def verify_recovery(runtime, name, database, identity, folder):
    """Load the fixed helper only for the explicitly selected recovery run."""
    spec = importlib.util.spec_from_file_location('dates_database_recovery', Path(__file__).with_name('dates-database-recovery.py'))
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    helper.verify(runtime, name, database, identity, folder, repository.client)


def main():
    """Run the fixed dates profile once; never pull, retry or touch regular data."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute-synthetic', action='store_true')
    parser.add_argument('--verify-recovery', action='store_true')
    parser.add_argument('--image', default='')
    args = parser.parse_args()
    try:
        if args.verify_recovery and not Path(__file__).with_name('dates-database-recovery.py').is_file():
            raise repository.client.Refusal('Recovery helper missing')
        repository.execute(Path(__file__).resolve().parent.parent, args,
                           repository.client.Runtime(seconds=120), profile='dates',
                           verification=verify_recovery if args.verify_recovery else None)
    except (repository.client.Refusal, OSError, ValueError):
        print('Dates fixture failed/refused; no retry, inspect retained evidence.')
        return 1
    print('Dates repository assertions completed; owned container stopped.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
