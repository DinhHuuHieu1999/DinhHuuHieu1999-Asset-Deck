"""Real daily recovery session adapter; construction has no OS side effects."""

import secrets
from daily_local_adapter import DailyAdapter
from daily_local_config import validate_config
from daily_local_environment import backend_environment
from daily_local_fixture_client import SyntheticClient
from daily_local_lifecycle import Launcher
from daily_local_session import SessionLock
from daily_local_profile import BASE, EXTENDED, profile_contract, profile_environment
from daily_local_extended_client import ExtendedClient


class RecoverySessions:
    """Retain every session before startup, including ambiguous startup failures.

    config contains validated absolute executable/TLS paths and explicit ports.
    The caller must probe all DB and listener ports before provisioning. The
    client is shared only to retain synthetic credentials across restore.
    """
    def __init__(self, config, runtime, client=None, adapter_factory=DailyAdapter,
                 launcher_factory=Launcher, lock_factory=SessionLock, profile=BASE):
        self.profile = profile_contract(profile)['name']
        self.config = validate_config(config)
        if self.config['app'] != self.config['python']:
            raise ValueError('Recovery accepts only the inert Python app substitute')
        self.runtime = runtime
        client_type = ExtendedClient if self.profile == EXTENDED else SyntheticClient
        self.client = client or client_type(config['https_port'], runtime.remaining)
        self.adapter_factory, self.launcher_factory = adapter_factory, launcher_factory
        self.lock_factory = lock_factory
        self.retained = []

    def open(self, database):
        """Start against the explicitly owned synthetic database, never a daily DB."""
        if self.profile != BASE and database.profile['name'] != self.profile:
            raise ValueError('Recovery database profile mismatch')
        database.assert_owned()
        private = dict(AUTH_POSTGRES_URL='postgresql://fixture:{}@127.0.0.1:{}/fixture'.format(
            database.password, database.port), JWT_ACCESS_SECRET=secrets.token_hex(32),
            CSRF_SECRET=secrets.token_hex(32))
        environment = (backend_environment(private, self.runtime.env) if self.profile == BASE
                       else profile_environment(self.profile, private, self.runtime.env))
        adapter = self.adapter_factory(self.config, environment)
        launcher = self.launcher_factory(adapter)
        session = RecoverySession(adapter, launcher,
            self.lock_factory(self.config['state_dir']), self.client, self.runtime.remaining)
        self.retained.append(session)
        session.lock.acquire()
        try:
            launcher.timeout = min(30, self.runtime.remaining())
            launcher.start()
        except Exception:
            session.close()
            raise
        return session

    def close_all(self):
        """Attempt graceful shutdown of every retained session without force kill."""
        failed = False
        for session in reversed(self.retained):
            try:
                session.close()
                if not session.clean(): failed = True
            except Exception:
                failed = True
        if failed:
            raise RuntimeError('Recovery session cleanup incomplete')


class RecoverySession:
    """Keep the real launcher handle and session token for explicit cleanup."""
    def __init__(self, adapter, launcher, lock, client, remaining):
        self.adapter, self.launcher, self.lock = adapter, launcher, lock
        self.client, self.remaining = client, remaining

    def seed(self):
        """Seed only through the normal synthetic HTTPS client."""
        return self.client.create_synthetic_asset()

    def login(self, asset_id):
        """Reauthenticate and compare the same asset on the restored database."""
        self.client.login_and_assert_asset(asset_id)
        return True

    def close(self):
        """Close the fixture-owned inert app, then stop backend/gateway gracefully."""
        item = self.adapter.processes.children.get('app')
        if item is not None:
            child = item[1]
            if child.poll() is None:
                child.stdin.close()
                child.wait(timeout=5)
        self.launcher.timeout = 30
        self.launcher.stop()
        if self.launcher.owned:
            raise RuntimeError('Recovery session still owns children')
        if self.lock.held:
            self.lock.release()

    def clean(self):
        """Confirm owned processes and the session lock are released."""
        return not self.launcher.owned and not self.lock.held
