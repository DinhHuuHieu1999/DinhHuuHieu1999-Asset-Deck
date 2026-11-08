"""Synthetic driver tests with no process, network, or container adapter."""

import unittest
from daily_local_acceptance import accept_session


class Lock:
    def __init__(self): self.held = False
    def acquire(self): self.held = True
    def release(self): self.held = False


class Launcher:
    def __init__(self, failure=None):
        self.owned = []
        self.failure = failure
        self.starts = 0
        self.stops = 0

    def start(self):
        self.starts += 1
        self.owned = ['synthetic']
        if self.failure == 'start': raise RuntimeError('start')

    def stop(self):
        self.stops += 1
        if self.failure == 'stop': raise RuntimeError('stop')
        self.owned = []


class Client:
    def __init__(self, failure=False): self.failure = failure
    def create_synthetic_asset(self):
        if self.failure: raise RuntimeError('synthetic HTTP failure')
        return 'synthetic-id'
    def assert_invalid_requests_rejected(self): pass
    def login_and_assert_asset(self, asset_id):
        assert asset_id == 'synthetic-id'


class AcceptanceTests(unittest.TestCase):
    def run_driver(self, launcher, lock, client=None):
        self.events = []
        return accept_session(launcher, lock, client or Client(), lambda: None,
                              lambda: 120, self.events.append)

    def test_two_starts_with_same_asset_and_released_lock(self):
        launcher, lock = Launcher(), Lock()
        result = self.run_driver(launcher, lock)
        self.assertEqual((launcher.starts, launcher.stops), (2, 2))
        self.assertFalse(lock.held)
        self.assertEqual(self.events, ['first-start', 'first-stop', 'restart-persistence'])
        self.assertEqual(result['nativeAcceptance'], 'not-tested-inert-substitute')

    def test_http_failure_cleans_once_without_restart(self):
        launcher, lock = Launcher(), Lock()
        with self.assertRaises(RuntimeError): self.run_driver(launcher, lock, Client(True))
        self.assertEqual((launcher.starts, launcher.stops), (1, 1))
        self.assertFalse(lock.held)

    def test_start_failure_still_cleans(self):
        launcher, lock = Launcher('start'), Lock()
        with self.assertRaises(RuntimeError): self.run_driver(launcher, lock)
        self.assertFalse(lock.held)

    def test_cleanup_failure_retains_lock_and_owned_state(self):
        launcher, lock = Launcher('stop'), Lock()
        with self.assertRaises(RuntimeError): self.run_driver(launcher, lock)
        self.assertTrue(lock.held)
        self.assertTrue(launcher.owned)
