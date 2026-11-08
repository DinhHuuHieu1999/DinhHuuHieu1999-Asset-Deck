"""Pure policy tests: no OS process, socket, database, or TLS access."""

import unittest
from daily_local_lifecycle import Launcher, LifecycleError


class Adapter:
    def __init__(self, failure=None):
        self.events = []
        self.failure = failure

    def preflight(self, timeout):
        self.events.append('preflight')
        if self.failure == 'preflight':
            raise RuntimeError('postgres://private-secret')

    def start(self, name, timeout):
        self.events.append('start:' + name)
        return (name, 'creation-identity')

    def ready(self, name, identity, timeout):
        if self.failure == name:
            raise RuntimeError('private TLS path')

    def matches(self, name, identity):
        return self.failure != 'ownership'

    def running(self, name, identity):
        return self.matches(name, identity)

    def stop(self, name, identity, timeout):
        self.events.append('stop:' + name)
        if self.failure == 'stop':
            raise RuntimeError('secret')


class LifecycleTests(unittest.TestCase):
    def test_start_and_reverse_stop(self):
        adapter = Adapter()
        launcher = Launcher(adapter)
        launcher.start()
        self.assertEqual(launcher.status(), dict.fromkeys(Launcher.COMPONENTS, True))
        launcher.stop()
        self.assertEqual(adapter.events, ['preflight', 'start:backend',
                         'start:gateway', 'start:app', 'stop:app',
                         'stop:gateway', 'stop:backend'])

    def test_preflight_failure_has_no_start_and_redacts(self):
        adapter = Adapter('preflight')
        with self.assertRaisesRegex(LifecycleError, '^Startup failed$'):
            Launcher(adapter).start()
        self.assertEqual(adapter.events, ['preflight'])

    def test_partial_failure_cleans_started_components(self):
        adapter = Adapter('gateway')
        with self.assertRaises(LifecycleError):
            Launcher(adapter).start()
        self.assertEqual(adapter.events[-2:], ['stop:gateway', 'stop:backend'])

    def test_mismatch_never_kills_and_retains_identity(self):
        adapter = Adapter()
        launcher = Launcher(adapter)
        launcher.start()
        adapter.failure = 'ownership'
        with self.assertRaises(LifecycleError):
            launcher.stop()
        self.assertEqual(len(launcher.owned), 3)
        self.assertFalse(any(event.startswith('stop:') for event in adapter.events))

    def test_stop_failure_retained(self):
        adapter = Adapter()
        launcher = Launcher(adapter)
        launcher.start()
        adapter.failure = 'stop'
        with self.assertRaises(LifecycleError):
            launcher.stop()
        self.assertEqual(len(launcher.owned), 3)

    def test_repeated_start_refused(self):
        launcher = Launcher(Adapter())
        launcher.start()
        with self.assertRaises(LifecycleError):
            launcher.start()

    def test_deadline_prevents_work(self):
        times = iter([0, 31, 31])
        adapter = Adapter()
        with self.assertRaises(LifecycleError):
            Launcher(adapter, clock=lambda: next(times)).start()
        self.assertEqual(adapter.events, [])

    def test_invalid_timeout(self):
        for value in (True, 0, -1, 121, '30', float('nan')):
            with self.assertRaises(ValueError):
                Launcher(Adapter(), timeout=value)


if __name__ == '__main__':
    unittest.main()
