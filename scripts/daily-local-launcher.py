"""Manual foreground launcher. No service starts without the explicit execute flag."""

import argparse
import json
import os
from pathlib import Path
import sys

from daily_local_adapter import DailyAdapter
from daily_local_config import validate_config
from daily_local_environment import backend_environment, SETTINGS, FEATURES
from daily_local_lifecycle import Launcher
from daily_local_session import SessionLock
from daily_local_profile import BASE, EXTENDED, profile_environment


def command_loop(launcher, input_stream, notify):
    """Accept fixed commands only; output labels never include submitted content."""
    for line in input_stream:
        command = line.strip()
        try:
            if command == 'start':
                launcher.start()
                notify('started')
            elif command == 'status':
                notify(json.dumps(launcher.status(), sort_keys=True))
            elif command in ('stop', 'quit'):
                launcher.stop()
                notify('stopped')
                if command == 'quit':
                    return True
            else:
                notify('Unknown command: use start, status, stop, or quit')
        except Exception:
            notify('Operation incomplete; close the app before stop and review owned state')
    try:
        launcher.stop()
    except Exception:
        notify('Session cleanup incomplete; lock retained for review')
        return False
    return True


def main(argv=None):
    """Load non-secret paths; private values come only from the parent environment."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--execute-approved-local', action='store_true')
    parser.add_argument('--profile', choices=(BASE, EXTENDED), default=None)
    args = parser.parse_args(argv)
    try:
        path = Path(args.config)
        if path.stat().st_size > 16384:
            raise ValueError('Configuration too large')
        with path.open('r', encoding='utf-8') as stream:
            config = validate_config(json.load(stream))
        if not args.execute_approved_local:
            print('Configuration paths validated; no processes started')
            return 0
        private = {name: os.environ[name] for name in SETTINGS + FEATURES if name in os.environ}
        environment = (backend_environment(private, os.environ) if args.profile is None
                       else profile_environment(args.profile, private, os.environ))
        lock = SessionLock(config['state_dir'])
        lock.acquire()
        launcher = Launcher(DailyAdapter(config, environment))
        print('Manual session ready: start, status, stop, quit; close app before stop')
        clean = command_loop(launcher, sys.stdin, print)
        if clean and not launcher.owned:
            lock.release()
            return 0
        return 1
    except Exception:
        print('Asset Desk launcher failed; review configuration and owned session state',
              file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
