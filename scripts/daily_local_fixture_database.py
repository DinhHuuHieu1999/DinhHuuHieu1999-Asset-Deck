"""Opt-in synthetic PostgreSQL lifecycle using a bounded subprocess adapter."""

import json
import re
import secrets
import time

from daily_local_profile import BASE, profile_contract


LABEL = 'asset-desk.daily-runtime'
MIGRATIONS = ('001-auth-accounts.sql', '002-assets.sql')


class SyntheticDatabase:
    """Create fresh labeled resources only; retain storage after verified stop."""

    def __init__(self, runtime, image, port, identity, clock=time.monotonic, sleep=time.sleep, profile=BASE):
        if (not re.fullmatch(r'sha256:[0-9a-f]{64}', image)
                or not re.fullmatch(r'[0-9a-f]{32}', identity)
                or type(port) is not int or not 1024 <= port <= 65535):
            raise ValueError('Invalid synthetic database identity')
        self.profile = profile_contract(profile)
        self.runtime, self.image, self.port = runtime, image, port
        self.identity, self.clock, self.sleep = identity, clock, sleep
        self.name = 'asset-daily-' + identity
        self.volume = self.name + '-data'
        self.password = secrets.token_hex(24)
        self.environment = dict(runtime.env, POSTGRES_PASSWORD=self.password,
                                PGPASSWORD=self.password)
        self.creation_attempted = False

    def assert_owned(self):
        """Inspect labels, never environment values; refuse unexpected ownership."""
        raw = self.runtime.run(['docker', 'inspect', '--format',
                                '{{json .Config.Labels}}', self.name])
        labels = json.loads(raw)
        if type(labels) is not dict or labels.get(LABEL) != self.identity:
            raise RuntimeError('Synthetic container ownership mismatch')

    def create(self):
        """No pull, bind mount, existing database, or remote listener is accepted."""
        actual = self.runtime.run(['docker', 'image', 'inspect', '--format', '{{.Id}}', self.image])
        if actual.decode().strip() != self.image:
            raise RuntimeError('Existing image identity mismatch')
        self.runtime.run(['docker', 'volume', 'create', '--label',
                          LABEL + '=' + self.identity, self.volume])
        # Even an ambiguous create timeout requires ownership review during cleanup.
        self.creation_attempted = True
        self.runtime.run(['docker', 'create', '--name', self.name, '--label',
                          LABEL + '=' + self.identity, '-e', 'POSTGRES_PASSWORD',
                          '-e', 'POSTGRES_USER=fixture', '-e', 'POSTGRES_DB=fixture',
                          '-p', '127.0.0.1:{}:5432'.format(self.port), '--mount',
                          'type=volume,src=' + self.volume + ',dst=/var/lib/postgresql/data',
                          self.image], env=self.environment)
        self.assert_owned()
        self.runtime.run(['docker', 'start', self.name])

    def wait_ready(self):
        """Readiness polling is bounded, and verifies both DB and role identity."""
        deadline = self.clock() + min(30, self.runtime.remaining())
        while self.clock() < deadline:
            try:
                raw = self.runtime.run(['docker', 'exec', '-e', 'PGPASSWORD',
                    '-e', 'PGCONNECT_TIMEOUT=2', self.name, 'psql', '-h', '127.0.0.1',
                    '-U', 'fixture', '-d', 'fixture', '-Atqc',
                    "SELECT current_database() || '|' || current_user"], env=self.environment)
            except Exception:
                self.sleep(min(0.1, max(0, deadline - self.clock())))
                continue
            if raw.decode().strip() != 'fixture|fixture':
                raise RuntimeError('Synthetic database identity mismatch')
            return
        raise RuntimeError('Synthetic database readiness deadline exceeded')

    def migrate(self, root):
        """Apply a fixed named synthetic schema, preloading before any SQL."""
        sql_files = [(root / 'backend' / 'migrations' / name).read_bytes()
                     for name in self.profile['migrations']]
        if any(not sql or len(sql) > 1024 * 1024 for sql in sql_files):
            raise ValueError('Invalid synthetic migration artifact')
        self.assert_owned()
        for sql in sql_files:
            self.assert_owned()
            self.runtime.run(['docker', 'exec', '-i', self.name, 'psql',
                              '-v', 'ON_ERROR_STOP=1', '-U', 'fixture', '-d', 'fixture'], data=sql)

    def stop(self):
        """Stop only the verified resource; never remove a container or volume."""
        if self.creation_attempted:
            self.assert_owned()
            self.runtime.run(['docker', 'stop', '--time', '10', self.name])
